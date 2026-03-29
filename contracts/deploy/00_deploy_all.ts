import { ethers } from "hardhat";
import { getSelectors } from "../test/helpers/deploy";

async function main() {
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log("Deploying ArcLend Diamond Protocol...");
  console.log("Deployer:", deployerAddress);
  console.log("Balance:", ethers.formatUnits(await ethers.provider.getBalance(deployerAddress), "ether"), "ETH");

  // ── Step 1: DiamondCutFacet (needed by Diamond constructor) ──────────────
  console.log("\n[1/5] Deploying DiamondCutFacet...");
  const DiamondCutFacet = await ethers.getContractFactory("DiamondCutFacet");
  const diamondCutFacet = await DiamondCutFacet.deploy();
  await diamondCutFacet.waitForDeployment();
  const diamondCutFacetAddress = await diamondCutFacet.getAddress();
  console.log("  DiamondCutFacet:", diamondCutFacetAddress);

  // ── Step 2: Diamond Proxy ────────────────────────────────────────────────
  console.log("[2/5] Deploying Diamond proxy...");
  const DiamondFactory = await ethers.getContractFactory("Diamond");
  const diamond = await DiamondFactory.deploy(deployerAddress, diamondCutFacetAddress);
  await diamond.waitForDeployment();
  const diamondAddress = await diamond.getAddress();
  console.log("  Diamond proxy:", diamondAddress);

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
    await facet.waitForDeployment();
    const facetAddress = await facet.getAddress();
    deployedFacets[name] = facetAddress;
    console.log(`  ${name}: ${facetAddress}`);
  }

  // ── Step 4: Deploy PriceOracle ───────────────────────────────────────────
  console.log("[4/5] Deploying PriceOracle...");
  const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
  const oracle = await PriceOracleFactory.deploy(deployerAddress);
  await oracle.waitForDeployment();
  const oracleAddress = await oracle.getAddress();
  console.log("  PriceOracle:", oracleAddress);

  // ── Step 5: Deploy DiamondInit and cut all facets in ────────────────────
  console.log("[5/5] Cutting facets into Diamond...");
  const DiamondInit = await ethers.getContractFactory("DiamondInit");
  const diamondInit = await DiamondInit.deploy();
  await diamondInit.waitForDeployment();
  const diamondInitAddress = await diamondInit.getAddress();

  const cut = [];
  for (const name of facetNames) {
    const facet = await ethers.getContractAt(name, deployedFacets[name]);
    cut.push({
      facetAddress: deployedFacets[name],
      action: 0, // Add
      functionSelectors: getSelectors(facet),
    });
  }

  const diamondCut = (await ethers.getContractAt("DiamondCutFacet", diamondAddress)) as unknown as any;
  const initCalldata = diamondInit.interface.encodeFunctionData("init", [
    deployerAddress,
    oracleAddress,
  ]);
  const tx = await diamondCut.diamondCut(cut, diamondInitAddress, initCalldata);
  await tx.wait();
  console.log("  All facets cut in successfully!");

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("\n═══════════════════════════════════════════════");
  console.log("  ArcLend Diamond Protocol Deployed!");
  console.log("  Diamond (proxy):    ", diamondAddress);
  console.log("  PriceOracle:        ", oracleAddress);
  console.log("  Deployer/Admin:     ", deployerAddress);
  console.log("═══════════════════════════════════════════════");
  console.log("\nSave DIAMOND_ADDRESS=" + diamondAddress + " in your .env");
  console.log("Save ORACLE_ADDRESS=" + oracleAddress + " in your .env");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
