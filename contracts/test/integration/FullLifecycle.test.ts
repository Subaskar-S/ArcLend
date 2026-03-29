import { expect } from "chai";
import { ethers, network } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
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
  let admin: HardhatEthersSigner;
  let alice: HardhatEthersSigner;
  let bob: HardhatEthersSigner;
  let liquidator: HardhatEthersSigner;
  
  let wethAddress: string;
  let usdcAddress: string;
  let diamondAddress: string;

  // Initial prices (WAD)
  let WETH_PRICE = ethers.parseEther("2000"); // $2000
  const USDC_PRICE = ethers.parseEther("1");   // $1

  const ALICE_USDC = ethers.parseUnits("50000", 6);
  const BOB_WETH = ethers.parseEther("10"); // 10 WETH = $20,000

  before(async function () {
    [admin, alice, bob, liquidator] = await ethers.getSigners();

    // Deploy Oracle
    const PO = await ethers.getContractFactory("PriceOracle");
    oracle = (await PO.deploy(admin.address)) as unknown as PriceOracle;
    await oracle.waitForDeployment();

    // Deploy Diamond
    diamond = await deployDiamond(admin.address, await oracle.getAddress());

    // Deploy tokens
    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    weth = (await ERC20.deploy("Wrapped Ether", "WETH", 18)) as unknown as ERC20Mock;
    await weth.waitForDeployment();
    usdc = (await ERC20.deploy("USD Coin", "USDC", 6)) as unknown as ERC20Mock;
    await usdc.waitForDeployment();

    // Deploy interest rate strategies
    const Strat = await ethers.getContractFactory("DefaultInterestRateStrategy");
    const strat = (await Strat.deploy(
      ethers.parseUnits("0.8", 27), 0,
      ethers.parseUnits("0.04", 27),
      ethers.parseUnits("0.75", 27)
    )) as unknown as DefaultInterestRateStrategy;
    await strat.waitForDeployment();

    // Deploy ATokens and DebtTokens
    const AT = await ethers.getContractFactory("AToken");
    const DT = await ethers.getContractFactory("DebtToken");

    diamondAddress = await diamond.diamond.getAddress();
    wethAddress = await weth.getAddress();
    usdcAddress = await usdc.getAddress();

    aWeth = (await AT.deploy(diamondAddress, wethAddress, "aWETH", "aWETH")) as unknown as AToken;
    await aWeth.waitForDeployment();
    aUsdc = (await AT.deploy(diamondAddress, usdcAddress, "aUSDC", "aUSDC")) as unknown as AToken;
    await aUsdc.waitForDeployment();
    
    const debtWeth = await DT.deploy(diamondAddress, wethAddress, "dWETH", "dWETH");
    await debtWeth.waitForDeployment();
    debtUsdc = (await DT.deploy(diamondAddress, usdcAddress, "dUSDC", "dUSDC")) as unknown as DebtToken;
    await debtUsdc.waitForDeployment();

    // Set prices
    await oracle.setAssetPrice(wethAddress, WETH_PRICE);
    await oracle.setAssetPrice(usdcAddress, USDC_PRICE);

    // Initialize reserves
    await diamond.configurator.initReserve(wethAddress, await aWeth.getAddress(), await debtWeth.getAddress(), await strat.getAddress());
    await diamond.configurator.setReserveConfiguration(wethAddress, 8000, 8500, 10500, 1000);

    await diamond.configurator.initReserve(usdcAddress, await aUsdc.getAddress(), await debtUsdc.getAddress(), await strat.getAddress());
    await diamond.configurator.setReserveConfiguration(usdcAddress, 8000, 8500, 10500, 1000);
    await diamond.configurator.setBorrowingEnabled(usdcAddress, true);

    // Approve and mint
    await usdc.mint(alice.address, ALICE_USDC);
    await weth.mint(bob.address, BOB_WETH);
    await usdc.mint(liquidator.address, ethers.parseUnits("100000", 6));

    await usdc.connect(alice).approve(diamondAddress, ethers.MaxUint256);
    await weth.connect(bob).approve(diamondAddress, ethers.MaxUint256);
    await usdc.connect(liquidator).approve(diamondAddress, ethers.MaxUint256);
  });

  it("Step 1: Alice deposits USDC", async function () {
    await diamond.lendingPool.connect(alice).deposit(usdcAddress, ALICE_USDC, alice.address);
    expect(await aUsdc.balanceOf(alice.address)).to.be.closeTo(ALICE_USDC, 1000n);
  });

  it("Step 2: Bob deposits WETH as collateral", async function () {
    await diamond.lendingPool.connect(bob).deposit(wethAddress, BOB_WETH, bob.address);
    expect(await aWeth.balanceOf(bob.address)).to.be.closeTo(BOB_WETH, ethers.parseEther("0.001"));
  });

  it("Step 3: Bob borrows USDC (within LTV)", async function () {
    // Bob has $20,000 WETH, 80% LTV = $16,000 USDC max
    const borrowAmount = ethers.parseUnits("10000", 6); // $10,000
    await diamond.borrow.connect(bob).borrow(usdcAddress, borrowAmount, bob.address);
    expect(await usdc.balanceOf(bob.address)).to.equal(borrowAmount);
  });

  it("Step 4+5: WETH price drops — Bob is liquidatable, liquidator liquidates Bob", async function () {
    // Drop WETH from $2000 to $500 — Bob's HF collapses
    await oracle.setAssetPrice(wethAddress, ethers.parseEther("700"));

    // Validate: Bob's HF < 1
    const [, , hf] = await diamond.view.getUserAccountData(bob.address);
    expect(hf).to.be.lessThan(ethers.parseEther("1"));

    const debtBefore = await debtUsdc.scaledBalanceOf(bob.address);
    const liquidatorWethBefore = await weth.balanceOf(liquidator.address);

    // Liquidator covers 50% of debt
    const halfDebt = ethers.parseUnits("5000", 6);
    await diamond.liquidation.connect(liquidator).liquidationCall(
      wethAddress,   // collateral
      usdcAddress,   // debt
      bob.address,
      halfDebt
    );

    const debtAfter = await debtUsdc.scaledBalanceOf(bob.address);
    expect(debtAfter).to.be.lessThan(debtBefore);

    const liquidatorWethAfter = await weth.balanceOf(liquidator.address);
    expect(liquidatorWethAfter).to.be.greaterThan(liquidatorWethBefore);
  });

  it("Verify: protocol state is consistent", async function () {
    const reserves = await diamond.view.getReservesList();
    expect(reserves.length).to.equal(2);
    expect(reserves).to.include(wethAddress);
    expect(reserves).to.include(usdcAddress);
  });
});
