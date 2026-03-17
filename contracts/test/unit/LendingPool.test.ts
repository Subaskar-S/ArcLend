import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { deployDiamond, DeployedDiamond } from "../helpers/deploy";
import {
  ERC20Mock,
  AToken,
  DebtToken,
  DefaultInterestRateStrategy,
  PriceOracle,
} from "../../typechain-types";

describe("LendingPoolFacet — deposit() and withdraw()", function () {
  let diamond: DeployedDiamond;
  let oracle: PriceOracle;
  let usdc: ERC20Mock;
  let aUsdc: AToken;
  let debtUsdc: DebtToken;
  let interestStrategy: DefaultInterestRateStrategy;
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  const USDC_DECIMALS = 6;
  const DEPOSIT_AMOUNT = ethers.utils.parseUnits("1000", USDC_DECIMALS); // 1000 USDC
  const USDC_PRICE = ethers.utils.parseEther("1"); // $1.00 in WAD

  beforeEach(async function () {
    [admin, alice, bob] = await ethers.getSigners();

    // Deploy PriceOracle
    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    oracle = (await PriceOracleFactory.deploy(admin.address)) as PriceOracle;

    // Deploy Diamond
    diamond = await deployDiamond(admin.address, oracle.address);

    // Deploy mock ERC20 (USDC)
    const ERC20MockFactory = await ethers.getContractFactory("ERC20Mock");
    usdc = (await ERC20MockFactory.deploy("USD Coin", "USDC", 6)) as ERC20Mock;

    // Deploy interest rate strategy
    const StrategyFactory = await ethers.getContractFactory("DefaultInterestRateStrategy");
    interestStrategy = (await StrategyFactory.deploy(
      ethers.utils.parseUnits("0.8", 27), // 80% optimal utilization
      0,                                   // 0% base rate
      ethers.utils.parseUnits("0.04", 27), // 4% slope1
      ethers.utils.parseUnits("0.75", 27)  // 75% slope2
    )) as DefaultInterestRateStrategy;

    // Deploy AToken and DebtToken for USDC
    const ATokenFactory = await ethers.getContractFactory("AToken");
    aUsdc = (await ATokenFactory.deploy(
      diamond.diamond.address,
      usdc.address,
      "Aave USDC",
      "aUSDC"
    )) as AToken;

    const DebtTokenFactory = await ethers.getContractFactory("DebtToken");
    debtUsdc = (await DebtTokenFactory.deploy(
      diamond.diamond.address,
      usdc.address,
      "Debt USDC",
      "dUSDC"
    )) as DebtToken;

    // Set oracle price for USDC
    await oracle.setAssetPrice(usdc.address, USDC_PRICE);

    // Initialize USDC reserve
    await diamond.configurator.initReserve(
      usdc.address,
      aUsdc.address,
      debtUsdc.address,
      interestStrategy.address
    );

    // Configure the reserve
    await diamond.configurator.setReserveConfiguration(
      usdc.address,
      8000,   // 80% LTV
      8500,   // 85% liquidation threshold
      10500,  // 105% liquidation bonus (5% bonus)
      1000    // 10% reserve factor
    );

    // Enable borrowing
    await diamond.configurator.setBorrowingEnabled(usdc.address, true);

    // Mint USDC to Alice and Bob
    await usdc.mint(alice.address, ethers.utils.parseUnits("10000", USDC_DECIMALS));
    await usdc.mint(bob.address, ethers.utils.parseUnits("10000", USDC_DECIMALS));
  });

  // ─── deposit() ────────────────────────────────────────────────────────

  describe("deposit()", function () {
    it("should emit Deposit event", async function () {
      await usdc.connect(alice).approve(diamond.diamond.address, DEPOSIT_AMOUNT);
      await expect(
        diamond.lendingPool.connect(alice).deposit(usdc.address, DEPOSIT_AMOUNT, alice.address)
      ).to.emit(diamond.lendingPool, "Deposit")
        .withArgs(usdc.address, alice.address, alice.address, DEPOSIT_AMOUNT);
    });

    it("should transfer USDC from depositor to aToken", async function () {
      await usdc.connect(alice).approve(diamond.diamond.address, DEPOSIT_AMOUNT);
      const balanceBefore = await usdc.balanceOf(aUsdc.address);
      await diamond.lendingPool.connect(alice).deposit(usdc.address, DEPOSIT_AMOUNT, alice.address);
      const balanceAfter = await usdc.balanceOf(aUsdc.address);
      expect(balanceAfter.sub(balanceBefore)).to.equal(DEPOSIT_AMOUNT);
    });

    it("should mint aTokens to depositor", async function () {
      await usdc.connect(alice).approve(diamond.diamond.address, DEPOSIT_AMOUNT);
      const aBalanceBefore = await aUsdc.balanceOf(alice.address);
      await diamond.lendingPool.connect(alice).deposit(usdc.address, DEPOSIT_AMOUNT, alice.address);
      const aBalanceAfter = await aUsdc.balanceOf(alice.address);
      // aBalance should approximately equal DEPOSIT_AMOUNT (index = 1 on fresh pool)
      expect(aBalanceAfter.sub(aBalanceBefore)).to.be.closeTo(DEPOSIT_AMOUNT, 100);
    });

    it("should revert on zero amount", async function () {
      await expect(
        diamond.lendingPool.connect(alice).deposit(usdc.address, 0, alice.address)
      ).to.be.revertedWith("VL: INVALID_AMOUNT");
    });

    it("should revert on inactive reserve", async function () {
      const FakeTokenFactory = await ethers.getContractFactory("ERC20Mock");
      const fake = await FakeTokenFactory.deploy("Fake", "FAKE", 18);
      await expect(
        diamond.lendingPool.connect(alice).deposit(fake.address, DEPOSIT_AMOUNT, alice.address)
      ).to.be.revertedWith("VL: RESERVE_INACTIVE");
    });

    it("should revert when protocol is paused", async function () {
      await diamond.configurator.connect(admin).pause();
      await usdc.connect(alice).approve(diamond.diamond.address, DEPOSIT_AMOUNT);
      await expect(
        diamond.lendingPool.connect(alice).deposit(usdc.address, DEPOSIT_AMOUNT, alice.address)
      ).to.be.revertedWith("Protocol: paused");
    });
  });

  // ─── withdraw() ───────────────────────────────────────────────────────

  describe("withdraw()", function () {
    beforeEach(async function () {
      await usdc.connect(alice).approve(diamond.diamond.address, DEPOSIT_AMOUNT);
      await diamond.lendingPool.connect(alice).deposit(usdc.address, DEPOSIT_AMOUNT, alice.address);
    });

    it("should emit Withdraw event", async function () {
      await expect(
        diamond.lendingPool.connect(alice).withdraw(usdc.address, DEPOSIT_AMOUNT, alice.address)
      ).to.emit(diamond.lendingPool, "Withdraw");
    });

    it("should return USDC to withdrawer", async function () {
      const balanceBefore = await usdc.balanceOf(alice.address);
      await diamond.lendingPool.connect(alice).withdraw(usdc.address, DEPOSIT_AMOUNT, alice.address);
      const balanceAfter = await usdc.balanceOf(alice.address);
      expect(balanceAfter.sub(balanceBefore)).to.be.closeTo(DEPOSIT_AMOUNT, 100);
    });

    it("should burn aTokens on withdrawal", async function () {
      const aBalanceBefore = await aUsdc.balanceOf(alice.address);
      await diamond.lendingPool.connect(alice).withdraw(usdc.address, DEPOSIT_AMOUNT, alice.address);
      const aBalanceAfter = await aUsdc.balanceOf(alice.address);
      expect(aBalanceAfter).to.be.lt(aBalanceBefore);
    });

    it("should withdraw full balance with type(uint256).max", async function () {
      const balanceBefore = await usdc.balanceOf(alice.address);
      await diamond.lendingPool.connect(alice).withdraw(
        usdc.address,
        ethers.constants.MaxUint256,
        alice.address
      );
      const balanceAfter = await usdc.balanceOf(alice.address);
      expect(balanceAfter).to.be.gte(balanceBefore);
      // aToken balance should be ~0
      expect(await aUsdc.balanceOf(alice.address)).to.equal(0);
    });
  });
});
