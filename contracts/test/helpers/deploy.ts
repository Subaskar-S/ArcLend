import { ethers } from "hardhat";
import {
  DiamondCutFacet,
  DiamondLoupeFacet,
  OwnershipFacet,
  LendingPoolFacet,
  BorrowFacet,
  LiquidationFacet,
  ConfiguratorFacet,
  ViewFacet,
  DiamondInit,
  Diamond,
} from "../../typechain-types";

export interface FacetCut {
  facetAddress: string;
  action: 0 | 1 | 2; // Add, Replace, Remove
  functionSelectors: string[];
}

export interface DeployedDiamond {
  diamond: Diamond;
  lendingPool: LendingPoolFacet;
  borrow: BorrowFacet;
  liquidation: LiquidationFacet;
  configurator: ConfiguratorFacet;
  view: ViewFacet;
  owner: DiamondCutFacet;
}

/**
 * Get the 4-byte function selectors for a contract's ABI
 */
export function getSelectors(contract: any): string[] {
  const selectors: string[] = [];
  contract.interface.forEachFunction((func: any) => {
    if (func.name !== "init") {
      selectors.push(func.selector);
    }
  });
  return selectors;
}

/**
 * Deploy the full protocol Diamond and cut all facets in.
 */
export async function deployDiamond(adminAddress: string, oracleAddress: string): Promise<DeployedDiamond> {
  const [deployer] = await ethers.getSigners();

  // Deploy facets
  const DiamondCutFacetFactory = await ethers.getContractFactory("DiamondCutFacet");
  const diamondCutFacet = await DiamondCutFacetFactory.deploy();
  await diamondCutFacet.waitForDeployment();

  // Deploy Diamond proxy
  const DiamondFactory = await ethers.getContractFactory("Diamond");
  const diamond = await DiamondFactory.deploy(adminAddress, diamondCutFacet.target);
  await diamond.waitForDeployment();

  // Deploy remaining facets
  const DiamondLoupeFacetFactory = await ethers.getContractFactory("DiamondLoupeFacet");
  const diamondLoupeFacet = await DiamondLoupeFacetFactory.deploy();
  await diamondLoupeFacet.waitForDeployment();

  const OwnershipFacetFactory = await ethers.getContractFactory("OwnershipFacet");
  const ownershipFacet = await OwnershipFacetFactory.deploy();
  await ownershipFacet.waitForDeployment();

  const LendingPoolFacetFactory = await ethers.getContractFactory("LendingPoolFacet");
  const lendingPoolFacet = await LendingPoolFacetFactory.deploy();
  await lendingPoolFacet.waitForDeployment();

  const BorrowFacetFactory = await ethers.getContractFactory("BorrowFacet");
  const borrowFacet = await BorrowFacetFactory.deploy();
  await borrowFacet.waitForDeployment();

  const LiquidationFacetFactory = await ethers.getContractFactory("LiquidationFacet");
  const liquidationFacet = await LiquidationFacetFactory.deploy();
  await liquidationFacet.waitForDeployment();

  const ConfiguratorFacetFactory = await ethers.getContractFactory("ConfiguratorFacet");
  const configuratorFacet = await ConfiguratorFacetFactory.deploy();
  await configuratorFacet.waitForDeployment();

  const ViewFacetFactory = await ethers.getContractFactory("ViewFacet");
  const viewFacet = await ViewFacetFactory.deploy();
  await viewFacet.waitForDeployment();

  const DiamondInitFactory = await ethers.getContractFactory("DiamondInit");
  const diamondInit = await DiamondInitFactory.deploy();
  await diamondInit.waitForDeployment();

  // Build the cut
  const cut: FacetCut[] = [
    { facetAddress: await diamondLoupeFacet.getAddress(), action: 0, functionSelectors: getSelectors(diamondLoupeFacet) },
    { facetAddress: await ownershipFacet.getAddress(), action: 0, functionSelectors: getSelectors(ownershipFacet) },
    { facetAddress: await lendingPoolFacet.getAddress(), action: 0, functionSelectors: getSelectors(lendingPoolFacet) },
    { facetAddress: await borrowFacet.getAddress(), action: 0, functionSelectors: getSelectors(borrowFacet) },
    { facetAddress: await liquidationFacet.getAddress(), action: 0, functionSelectors: getSelectors(liquidationFacet) },
    { facetAddress: await configuratorFacet.getAddress(), action: 0, functionSelectors: getSelectors(configuratorFacet) },
    { facetAddress: await viewFacet.getAddress(), action: 0, functionSelectors: getSelectors(viewFacet) },
  ];

  // Execute the diamond cut with init
  const diamondInstanceAddress = await diamond.getAddress();
  const diamondCut = (await ethers.getContractAt("DiamondCutFacet", diamondInstanceAddress)) as unknown as DiamondCutFacet;
  const initCalldata = diamondInit.interface.encodeFunctionData("init", [adminAddress, oracleAddress]);
  const tx = await diamondCut.diamondCut(cut, await diamondInit.getAddress(), initCalldata);
  await tx.wait();

  return {
    diamond: diamond as unknown as Diamond,
    lendingPool: (await ethers.getContractAt("LendingPoolFacet", diamondInstanceAddress)) as unknown as LendingPoolFacet,
    borrow: (await ethers.getContractAt("BorrowFacet", diamondInstanceAddress)) as unknown as BorrowFacet,
    liquidation: (await ethers.getContractAt("LiquidationFacet", diamondInstanceAddress)) as unknown as LiquidationFacet,
    configurator: (await ethers.getContractAt("ConfiguratorFacet", diamondInstanceAddress)) as unknown as ConfiguratorFacet,
    view: (await ethers.getContractAt("ViewFacet", diamondInstanceAddress)) as unknown as ViewFacet,
    owner: diamondCut,
  };
}
