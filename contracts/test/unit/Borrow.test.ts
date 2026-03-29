import { expect } from "chai";
import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
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
  let admin: HardhatEthersSigner;
  let alice: HardhatEthersSigner; // Depositor of collateral (WETH)
  let bob: HardhatEthersSigner;   // Borrower of USDC

  const WETH_PRICE = ethers.parseEther("2000"); // $2000/ETH
  const USDC_PRICE = ethers.parseEther("1");    // $1/USDC
  const COLLATERAL = ethers.parseEther("1");    // 1 WETH 
  const BORROW_AMOUNT = ethers.parseUnits("1200", 6); // 1200 USDC (60% of $2000 collateral)

  beforeEach(async function () {
    [admin, alice, bob] = await ethers.getSigners();

    const PO = await ethers.getContractFactory("PriceOracle");
    oracle = (await PO.deploy(admin.address)) as unknown as PriceOracle;
    await oracle.waitForDeployment();
    diamond = await deployDiamond(admin.address, await oracle.getAddress());

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    weth = (await ERC20.deploy("Wrapped Ether", "WETH", 18)) as unknown as ERC20Mock;
    await weth.waitForDeployment();
    usdc = (await ERC20.deploy("USD Coin", "USDC", 6)) as unknown as ERC20Mock;
    await usdc.waitForDeployment();

    const Strat = await ethers.getContractFactory("DefaultInterestRateStrategy");
    const wethStrat = (await Strat.deploy(
      ethers.parseUnits("0.8", 27), 0,
      ethers.parseUnits("0.04", 27),
      ethers.parseUnits("0.75", 27)
    )) as unknown as DefaultInterestRateStrategy;
    await wethStrat.waitForDeployment();
    const usdcStrat = (await Strat.deploy(
      ethers.parseUnits("0.8", 27), 0,
      ethers.parseUnits("0.06", 27),
      ethers.parseUnits("0.75", 27)
    )) as unknown as DefaultInterestRateStrategy;
    await usdcStrat.waitForDeployment();

    const AT = await ethers.getContractFactory("AToken");
    const diamondAddress = await diamond.diamond.getAddress();
    aWeth = (await AT.deploy(diamondAddress, await weth.getAddress(), "aWETH", "aWETH")) as unknown as AToken;
    await aWeth.waitForDeployment();
    aUsdc = (await AT.deploy(diamondAddress, await usdc.getAddress(), "aUSDC", "aUSDC")) as unknown as AToken;
    await aUsdc.waitForDeployment();

    const DT = await ethers.getContractFactory("DebtToken");
    debtUsdc = (await DT.deploy(diamondAddress, await usdc.getAddress(), "dUSDC", "dUSDC")) as unknown as DebtToken;
    await debtUsdc.waitForDeployment();

    // Oracle prices
    const wethAddress = await weth.getAddress();
    const usdcAddress = await usdc.getAddress();
    await oracle.setAssetPrice(wethAddress, WETH_PRICE);
    await oracle.setAssetPrice(usdcAddress, USDC_PRICE);

    // Initialize reserves
    const dWeth = (await (await ethers.getContractFactory("DebtToken")).deploy(diamondAddress, wethAddress, "dWETH", "dWETH"));
    await dWeth.waitForDeployment();
    await diamond.configurator.initReserve(wethAddress, await aWeth.getAddress(),
      await dWeth.getAddress(),
      await wethStrat.getAddress()
    );
    await diamond.configurator.setReserveConfiguration(wethAddress, 8000, 8500, 10500, 1000);

    await diamond.configurator.initReserve(usdcAddress, await aUsdc.getAddress(), await debtUsdc.getAddress(), await usdcStrat.getAddress());
    await diamond.configurator.setReserveConfiguration(usdcAddress, 8000, 8500, 10500, 1000);
    await diamond.configurator.setBorrowingEnabled(usdcAddress, true);

    // Alice deposits WETH as collateral
    await weth.mint(alice.address, ethers.parseEther("10"));
    await weth.connect(alice).approve(diamondAddress, ethers.MaxUint256);
    await diamond.lendingPool.connect(alice).deposit(wethAddress, COLLATERAL, alice.address);

    // Fund liquidity pool with USDC (so borrowing is possible)
    await usdc.mint(admin.address, ethers.parseUnits("100000", 6));
    await usdc.connect(admin).approve(diamondAddress, ethers.MaxUint256);
    await diamond.lendingPool.connect(admin).deposit(usdcAddress, ethers.parseUnits("50000", 6), admin.address);
  });

  describe("borrow()", function () {
    it("should emit Borrow event", async function () {
      await expect(
        diamond.borrow.connect(alice).borrow(await usdc.getAddress(), BORROW_AMOUNT, alice.address)
      ).to.emit(diamond.borrow, "Borrow");
    });

    it("should transfer USDC to borrower", async function () {
      const before = await usdc.balanceOf(alice.address);
      await diamond.borrow.connect(alice).borrow(await usdc.getAddress(), BORROW_AMOUNT, alice.address);
      const after = await usdc.balanceOf(alice.address);
      expect(after - before).to.equal(BORROW_AMOUNT);
    });

    it("should mint debt tokens", async function () {
      await diamond.borrow.connect(alice).borrow(await usdc.getAddress(), BORROW_AMOUNT, alice.address);
      const debtBalance = await debtUsdc.scaledBalanceOf(alice.address);
      expect(debtBalance).to.be.greaterThan(0n);
    });

    it("should revert if health factor would drop below 1", async function () {
      // Bob has 1 WETH collateral = $2000. LTV is 80%, but liquidation threshold is 85% ($1700).
      const tooMuch = ethers.parseUnits("1800", 6); // Exceeds the 85% Liquidation Threshold ($1700)
      await expect(
        diamond.borrow.connect(alice).borrow(await usdc.getAddress(), tooMuch, alice.address)
      ).to.be.revertedWith("VL: HEALTH_FACTOR_BELOW_1");
    });

    it("should revert if borrowing not enabled", async function () {
      // WETH borrowing is disabled — try to borrow WETH
      await expect(
        diamond.borrow.connect(alice).borrow(await weth.getAddress(), ethers.parseEther("0.1"), alice.address)
      ).to.be.revertedWith("VL: BORROWING_NOT_ENABLED");
    });
  });

  describe("repay()", function () {
    beforeEach(async function () {
      await diamond.borrow.connect(alice).borrow(await usdc.getAddress(), BORROW_AMOUNT, alice.address);
    });

    it("should emit Repay event", async function () {
      await usdc.connect(alice).approve(await diamond.diamond.getAddress(), BORROW_AMOUNT);
      await expect(
        diamond.borrow.connect(alice).repay(await usdc.getAddress(), BORROW_AMOUNT, alice.address)
      ).to.emit(diamond.borrow, "Repay");
    });

    it("should reduce debt balance", async function () {
      const debtBefore = await debtUsdc.scaledBalanceOf(alice.address);
      await usdc.connect(alice).approve(await diamond.diamond.getAddress(), BORROW_AMOUNT);
      await diamond.borrow.connect(alice).repay(await usdc.getAddress(), BORROW_AMOUNT, alice.address);
      const debtAfter = await debtUsdc.scaledBalanceOf(alice.address);
      expect(debtAfter).to.be.lessThan(debtBefore);
    });

    it("should collect repayment from repayer", async function () {
      const aUsdcAddress = await aUsdc.getAddress();
      const aTokenBefore = await usdc.balanceOf(aUsdcAddress);
      await usdc.connect(alice).approve(await diamond.diamond.getAddress(), BORROW_AMOUNT);
      await diamond.borrow.connect(alice).repay(await usdc.getAddress(), BORROW_AMOUNT, alice.address);
      const aTokenAfter = await usdc.balanceOf(aUsdcAddress);
      expect(aTokenAfter).to.be.greaterThan(aTokenBefore);
    });

    it("should repay full debt with type(uint256).max", async function () {
      await usdc.connect(alice).approve(await diamond.diamond.getAddress(), ethers.MaxUint256);
      await diamond.borrow.connect(alice).repay(await usdc.getAddress(), ethers.MaxUint256, alice.address);
      expect(await debtUsdc.scaledBalanceOf(alice.address)).to.equal(0n);
    });
  });
});
