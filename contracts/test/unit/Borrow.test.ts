import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployDiamond, DeployedDiamond } from "../helpers/deploy";
import { ERC20Mock, AToken, DebtToken, DefaultInterestRateStrategy, PriceOracle } from "../../typechain-types";

describe("BorrowFacet — borrow() and repay()", function () {
  let diamond: DeployedDiamond;
  let oracle: PriceOracle;
  let weth: ERC20Mock;
  let usdc: ERC20Mock;
  let aWeth: AToken;
  let aUsdc: AToken;
  let debtUsdc: DebtToken;
  let admin: SignerWithAddress;
  let alice: SignerWithAddress; // Depositor of collateral (WETH)
  let bob: SignerWithAddress;   // Borrower of USDC

  const WETH_PRICE = ethers.utils.parseEther("2000"); // $2000/ETH
  const USDC_PRICE = ethers.utils.parseEther("1");    // $1/USDC
  const COLLATERAL = ethers.utils.parseEther("1");    // 1 WETH 
  const BORROW_AMOUNT = ethers.utils.parseUnits("1200", 6); // 1200 USDC (60% of $2000 collateral)

  beforeEach(async function () {
    [admin, alice, bob] = await ethers.getSigners();

    const PO = await ethers.getContractFactory("PriceOracle");
    oracle = (await PO.deploy(admin.address)) as PriceOracle;
    diamond = await deployDiamond(admin.address, oracle.address);

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    weth = (await ERC20.deploy("Wrapped Ether", "WETH", 18)) as ERC20Mock;
    usdc = (await ERC20.deploy("USD Coin", "USDC", 6)) as ERC20Mock;

    const Strat = await ethers.getContractFactory("DefaultInterestRateStrategy");
    const wethStrat = (await Strat.deploy(
      ethers.utils.parseUnits("0.8", 27), 0,
      ethers.utils.parseUnits("0.04", 27),
      ethers.utils.parseUnits("0.75", 27)
    )) as DefaultInterestRateStrategy;
    const usdcStrat = (await Strat.deploy(
      ethers.utils.parseUnits("0.8", 27), 0,
      ethers.utils.parseUnits("0.06", 27),
      ethers.utils.parseUnits("0.75", 27)
    )) as DefaultInterestRateStrategy;

    const AT = await ethers.getContractFactory("AToken");
    aWeth = (await AT.deploy(diamond.diamond.address, weth.address, "aWETH", "aWETH")) as AToken;
    aUsdc = (await AT.deploy(diamond.diamond.address, usdc.address, "aUSDC", "aUSDC")) as AToken;

    const DT = await ethers.getContractFactory("DebtToken");
    debtUsdc = (await DT.deploy(diamond.diamond.address, usdc.address, "dUSDC", "dUSDC")) as DebtToken;

    // Oracle prices
    await oracle.setAssetPrice(weth.address, WETH_PRICE);
    await oracle.setAssetPrice(usdc.address, USDC_PRICE);

    // Initialize reserves
    await diamond.configurator.initReserve(weth.address, aWeth.address,
      (await (await ethers.getContractFactory("DebtToken")).deploy(diamond.diamond.address, weth.address, "dWETH", "dWETH")).address,
      wethStrat.address
    );
    await diamond.configurator.setReserveConfiguration(weth.address, 8000, 8500, 10500, 1000);

    await diamond.configurator.initReserve(usdc.address, aUsdc.address, debtUsdc.address, usdcStrat.address);
    await diamond.configurator.setReserveConfiguration(usdc.address, 8000, 8500, 10500, 1000);
    await diamond.configurator.setBorrowingEnabled(usdc.address, true);

    // Alice deposits WETH as collateral
    await weth.mint(alice.address, ethers.utils.parseEther("10"));
    await weth.connect(alice).approve(diamond.diamond.address, ethers.constants.MaxUint256);
    await diamond.lendingPool.connect(alice).deposit(weth.address, COLLATERAL, alice.address);

    // Fund liquidity pool with USDC (so borrowing is possible)
    await usdc.mint(admin.address, ethers.utils.parseUnits("100000", 6));
    await usdc.connect(admin).approve(diamond.diamond.address, ethers.constants.MaxUint256);
    await diamond.lendingPool.connect(admin).deposit(usdc.address, ethers.utils.parseUnits("50000", 6), admin.address);
  });

  describe("borrow()", function () {
    it("should emit Borrow event", async function () {
      await expect(
        diamond.borrow.connect(alice).borrow(usdc.address, BORROW_AMOUNT, alice.address)
      ).to.emit(diamond.borrow, "Borrow");
    });

    it("should transfer USDC to borrower", async function () {
      const before = await usdc.balanceOf(alice.address);
      await diamond.borrow.connect(alice).borrow(usdc.address, BORROW_AMOUNT, alice.address);
      const after = await usdc.balanceOf(alice.address);
      expect(after.sub(before)).to.equal(BORROW_AMOUNT);
    });

    it("should mint debt tokens", async function () {
      await diamond.borrow.connect(alice).borrow(usdc.address, BORROW_AMOUNT, alice.address);
      const debtBalance = await debtUsdc.scaledBalanceOf(alice.address);
      expect(debtBalance).to.be.gt(0);
    });

    it("should revert if health factor would drop below 1", async function () {
      const tooMuch = ethers.utils.parseUnits("1900", 6); // >80% LTV of $2000
      await expect(
        diamond.borrow.connect(alice).borrow(usdc.address, tooMuch, alice.address)
      ).to.be.revertedWith("VL: HEALTH_FACTOR_BELOW_1");
    });

    it("should revert if borrowing not enabled", async function () {
      // WETH borrowing is disabled — try to borrow WETH
      await expect(
        diamond.borrow.connect(alice).borrow(weth.address, ethers.utils.parseEther("0.1"), alice.address)
      ).to.be.revertedWith("VL: BORROWING_NOT_ENABLED");
    });
  });

  describe("repay()", function () {
    beforeEach(async function () {
      await diamond.borrow.connect(alice).borrow(usdc.address, BORROW_AMOUNT, alice.address);
    });

    it("should emit Repay event", async function () {
      await usdc.connect(alice).approve(diamond.diamond.address, BORROW_AMOUNT);
      await expect(
        diamond.borrow.connect(alice).repay(usdc.address, BORROW_AMOUNT, alice.address)
      ).to.emit(diamond.borrow, "Repay");
    });

    it("should reduce debt balance", async function () {
      const debtBefore = await debtUsdc.scaledBalanceOf(alice.address);
      await usdc.connect(alice).approve(diamond.diamond.address, BORROW_AMOUNT);
      await diamond.borrow.connect(alice).repay(usdc.address, BORROW_AMOUNT, alice.address);
      const debtAfter = await debtUsdc.scaledBalanceOf(alice.address);
      expect(debtAfter).to.be.lt(debtBefore);
    });

    it("should collect repayment from repayer", async function () {
      const aTokenBefore = await usdc.balanceOf(aUsdc.address);
      await usdc.connect(alice).approve(diamond.diamond.address, BORROW_AMOUNT);
      await diamond.borrow.connect(alice).repay(usdc.address, BORROW_AMOUNT, alice.address);
      const aTokenAfter = await usdc.balanceOf(aUsdc.address);
      expect(aTokenAfter).to.be.gt(aTokenBefore);
    });

    it("should repay full debt with type(uint256).max", async function () {
      await usdc.connect(alice).approve(diamond.diamond.address, ethers.constants.MaxUint256);
      await diamond.borrow.connect(alice).repay(usdc.address, ethers.constants.MaxUint256, alice.address);
      expect(await debtUsdc.scaledBalanceOf(alice.address)).to.equal(0);
    });
  });
});
