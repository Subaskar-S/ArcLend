import { ethers } from "hardhat";
import { getSelectors } from "../test/helpers/deploy";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ArcLend Diamond Protocol...");
  console.log("Deployer:", deployer.address);
  console.log("Balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH");

  // ── Step 1: DiamondCutFacet (needed by Diamond constructor) ──────────────
  console.log("\n[1/5] Deploying DiamondCutFacet...");
  const DiamondCutFacet = await ethers.getContractFactory("DiamondCutFacet");
  const diamondCutFacet = await DiamondCutFacet.deploy();
  await diamondCutFacet.deployed();
  console.log("  DiamondCutFacet:", diamondCutFacet.address);

  // ── Step 2: Diamond Proxy ────────────────────────────────────────────────
  console.log("[2/5] Deploying Diamond proxy...");
  const DiamondFactory = await ethers.getContractFactory("Diamond");
  const diamond = await DiamondFactory.deploy(deployer.address, diamondCutFacet.address);
  await diamond.deployed();
  console.log("  Diamond proxy:", diamond.address);

  // ── Step 3: Deploy all remaining facets ─────────────────────────────────
  console.log("[3/5] Deploying all protocol facets...");
  const facetNames = [
    "DiamondLoupeFacet",
    "OwnershipFacet",
    "LendingPoolFacet",
    "BorrowFacet",
    "LiquidationFacet",
    "ConfiguratorFacet",
    "ViewFacet",
  ];

  const deployedFacets: Record<string, string> = {};
  for (const name of facetNames) {
    const Factory = await ethers.getContractFactory(name);
    const facet = await Factory.deploy();
    await facet.deployed();
    deployedFacets[name] = facet.address;
    console.log(`  ${name}: ${facet.address}`);
  }

  // ── Step 4: Deploy PriceOracle ───────────────────────────────────────────
  console.log("[4/5] Deploying PriceOracle...");
  const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
  const oracle = await PriceOracleFactory.deploy(deployer.address);
  await oracle.deployed();
  console.log("  PriceOracle:", oracle.address);

  // ── Step 5: Deploy DiamondInit and cut all facets in ────────────────────
  console.log("[5/5] Cutting facets into Diamond...");
  const DiamondInit = await ethers.getContractFactory("DiamondInit");
  const diamondInit = await DiamondInit.deploy();
  await diamondInit.deployed();

  const cut = [];
  for (const name of facetNames) {
    const facet = await ethers.getContractAt(name, deployedFacets[name]);
    cut.push({
      facetAddress: deployedFacets[name],
      action: 0, // Add
      functionSelectors: getSelectors(facet),
    });
  }

  const diamondCut = await ethers.getContractAt("DiamondCutFacet", diamond.address);
  const initCalldata = diamondInit.interface.encodeFunctionData("init", [
    deployer.address,
    oracle.address,
  ]);
  const tx = await diamondCut.diamondCut(cut, diamondInit.address, initCalldata);
  await tx.wait();
  console.log("  All facets cut in successfully!");

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("\n═══════════════════════════════════════════════");
  console.log("  ArcLend Diamond Protocol Deployed!");
  console.log("  Diamond (proxy):    ", diamond.address);
  console.log("  PriceOracle:        ", oracle.address);
  console.log("  Deployer/Admin:     ", deployer.address);
  console.log("═══════════════════════════════════════════════");
  console.log("\nSave DIAMOND_ADDRESS=" + diamond.address + " in your .env");
  console.log("Save ORACLE_ADDRESS=" + oracle.address + " in your .env");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
