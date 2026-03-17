import { expect } from "chai";
import { ethers, network } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployDiamond, DeployedDiamond } from "../helpers/deploy";
import { ERC20Mock, AToken, DebtToken, DefaultInterestRateStrategy, PriceOracle } from "../../typechain-types";

/**
 * Full lifecycle integration test:
 * 1. Alice deposits USDC as collateral
 * 2. Bob deposits WETH as collateral
 * 3. Bob borrows USDC
 * 4. WETH price drops → Bob's HF < 1
 * 5. Liquidator liquidates Bob
 * 6. Verify: Bob's debt reduced, liquidator received collateral
 */
describe("Full Protocol Lifecycle", function () {
  let diamond: DeployedDiamond;
  let oracle: PriceOracle;
  let weth: ERC20Mock;
  let usdc: ERC20Mock;
  let aWeth: AToken;
  let aUsdc: AToken;
  let debtUsdc: DebtToken;
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let liquidator: SignerWithAddress;

  // Initial prices (WAD)
  let WETH_PRICE = ethers.utils.parseEther("2000"); // $2000
  const USDC_PRICE = ethers.utils.parseEther("1");   // $1

  const ALICE_USDC = ethers.utils.parseUnits("50000", 6);
  const BOB_WETH = ethers.utils.parseEther("10"); // 10 WETH = $20,000

  before(async function () {
    [admin, alice, bob, liquidator] = await ethers.getSigners();

    // Deploy Oracle
    const PO = await ethers.getContractFactory("PriceOracle");
    oracle = (await PO.deploy(admin.address)) as PriceOracle;

    // Deploy Diamond
    diamond = await deployDiamond(admin.address, oracle.address);

    // Deploy tokens
    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    weth = (await ERC20.deploy("Wrapped Ether", "WETH", 18)) as ERC20Mock;
    usdc = (await ERC20.deploy("USD Coin", "USDC", 6)) as ERC20Mock;

    // Deploy interest rate strategies
    const Strat = await ethers.getContractFactory("DefaultInterestRateStrategy");
    const strat = (await Strat.deploy(
      ethers.utils.parseUnits("0.8", 27), 0,
      ethers.utils.parseUnits("0.04", 27),
      ethers.utils.parseUnits("0.75", 27)
    )) as DefaultInterestRateStrategy;

    // Deploy ATokens and DebtTokens
    const AT = await ethers.getContractFactory("AToken");
    const DT = await ethers.getContractFactory("DebtToken");

    aWeth = (await AT.deploy(diamond.diamond.address, weth.address, "aWETH", "aWETH")) as AToken;
    aUsdc = (await AT.deploy(diamond.diamond.address, usdc.address, "aUSDC", "aUSDC")) as AToken;
    const debtWeth = await DT.deploy(diamond.diamond.address, weth.address, "dWETH", "dWETH");
    debtUsdc = (await DT.deploy(diamond.diamond.address, usdc.address, "dUSDC", "dUSDC")) as DebtToken;

    // Set prices
    await oracle.setAssetPrice(weth.address, WETH_PRICE);
    await oracle.setAssetPrice(usdc.address, USDC_PRICE);

    // Initialize reserves
    await diamond.configurator.initReserve(weth.address, aWeth.address, debtWeth.address, strat.address);
    await diamond.configurator.setReserveConfiguration(weth.address, 8000, 8500, 10500, 1000);

    await diamond.configurator.initReserve(usdc.address, aUsdc.address, debtUsdc.address, strat.address);
    await diamond.configurator.setReserveConfiguration(usdc.address, 8000, 8500, 10500, 1000);
    await diamond.configurator.setBorrowingEnabled(usdc.address, true);

    // Approve and mint
    await usdc.mint(alice.address, ALICE_USDC);
    await weth.mint(bob.address, BOB_WETH);
    await usdc.mint(liquidator.address, ethers.utils.parseUnits("100000", 6));

    await usdc.connect(alice).approve(diamond.diamond.address, ethers.constants.MaxUint256);
    await weth.connect(bob).approve(diamond.diamond.address, ethers.constants.MaxUint256);
    await usdc.connect(liquidator).approve(diamond.diamond.address, ethers.constants.MaxUint256);
  });

  it("Step 1: Alice deposits USDC", async function () {
    await diamond.lendingPool.connect(alice).deposit(usdc.address, ALICE_USDC, alice.address);
    expect(await aUsdc.balanceOf(alice.address)).to.be.closeTo(ALICE_USDC, 1000);
  });

  it("Step 2: Bob deposits WETH as collateral", async function () {
    await diamond.lendingPool.connect(bob).deposit(weth.address, BOB_WETH, bob.address);
    expect(await aWeth.balanceOf(bob.address)).to.be.closeTo(BOB_WETH, ethers.utils.parseEther("0.001"));
  });

  it("Step 3: Bob borrows USDC (within LTV)", async function () {
    // Bob has $20,000 WETH, 80% LTV = $16,000 USDC max
    const borrowAmount = ethers.utils.parseUnits("10000", 6); // $10,000
    await diamond.borrow.connect(bob).borrow(usdc.address, borrowAmount, bob.address);
    expect(await usdc.balanceOf(bob.address)).to.equal(borrowAmount);
  });

  it("Step 4+5: WETH price drops — Bob is liquidatable, liquidator liquidates Bob", async function () {
    // Drop WETH from $2000 to $500 — Bob's HF collapses
    await oracle.setAssetPrice(weth.address, ethers.utils.parseEther("700"));

    // Validate: Bob's HF < 1
    const [, , hf] = await diamond.view.getUserAccountData(bob.address);
    expect(hf).to.be.lt(ethers.utils.parseEther("1"));

    const debtBefore = await debtUsdc.scaledBalanceOf(bob.address);
    const liquidatorWethBefore = await weth.balanceOf(liquidator.address);

    // Liquidator covers 50% of debt
    const halfDebt = ethers.utils.parseUnits("5000", 6);
    await diamond.liquidation.connect(liquidator).liquidationCall(
      weth.address,   // collateral
      usdc.address,   // debt
      bob.address,
      halfDebt
    );

    const debtAfter = await debtUsdc.scaledBalanceOf(bob.address);
    expect(debtAfter).to.be.lt(debtBefore);

    const liquidatorWethAfter = await weth.balanceOf(liquidator.address);
    expect(liquidatorWethAfter).to.be.gt(liquidatorWethBefore);
  });

  it("Verify: protocol state is consistent", async function () {
    const reserves = await diamond.view.getReservesList();
    expect(reserves.length).to.equal(2);
    expect(reserves).to.include(weth.address);
    expect(reserves).to.include(usdc.address);
  });
});
