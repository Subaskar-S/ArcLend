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
} from "../typechain-types";

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
  const signatures = Object.keys(contract.interface.functions);
  return signatures
    .filter((sig) => sig !== "init(bytes)") // exclude init
    .map((sig) => contract.interface.getSighash(sig));
}

/**
 * Deploy the full protocol Diamond and cut all facets in.
 */
export async function deployDiamond(adminAddress: string, oracleAddress: string): Promise<DeployedDiamond> {
  const [deployer] = await ethers.getSigners();

  // Deploy facets
  const DiamondCutFacetFactory = await ethers.getContractFactory("DiamondCutFacet");
  const diamondCutFacet = await DiamondCutFacetFactory.deploy();
  await diamondCutFacet.deployed();

  // Deploy Diamond proxy
  const DiamondFactory = await ethers.getContractFactory("Diamond");
  const diamond = await DiamondFactory.deploy(adminAddress, diamondCutFacet.address);
  await diamond.deployed();

  // Deploy remaining facets
  const DiamondLoupeFacetFactory = await ethers.getContractFactory("DiamondLoupeFacet");
  const diamondLoupeFacet = await DiamondLoupeFacetFactory.deploy();
  await diamondLoupeFacet.deployed();

  const OwnershipFacetFactory = await ethers.getContractFactory("OwnershipFacet");
  const ownershipFacet = await OwnershipFacetFactory.deploy();
  await ownershipFacet.deployed();

  const LendingPoolFacetFactory = await ethers.getContractFactory("LendingPoolFacet");
  const lendingPoolFacet = await LendingPoolFacetFactory.deploy();
  await lendingPoolFacet.deployed();

  const BorrowFacetFactory = await ethers.getContractFactory("BorrowFacet");
  const borrowFacet = await BorrowFacetFactory.deploy();
  await borrowFacet.deployed();

  const LiquidationFacetFactory = await ethers.getContractFactory("LiquidationFacet");
  const liquidationFacet = await LiquidationFacetFactory.deploy();
  await liquidationFacet.deployed();

  const ConfiguratorFacetFactory = await ethers.getContractFactory("ConfiguratorFacet");
  const configuratorFacet = await ConfiguratorFacetFactory.deploy();
  await configuratorFacet.deployed();

  const ViewFacetFactory = await ethers.getContractFactory("ViewFacet");
  const viewFacet = await ViewFacetFactory.deploy();
  await viewFacet.deployed();

  const DiamondInitFactory = await ethers.getContractFactory("DiamondInit");
  const diamondInit = await DiamondInitFactory.deploy();
  await diamondInit.deployed();

  // Build the cut
  const cut: FacetCut[] = [
    { facetAddress: diamondLoupeFacet.address, action: 0, functionSelectors: getSelectors(diamondLoupeFacet) },
    { facetAddress: ownershipFacet.address, action: 0, functionSelectors: getSelectors(ownershipFacet) },
    { facetAddress: lendingPoolFacet.address, action: 0, functionSelectors: getSelectors(lendingPoolFacet) },
    { facetAddress: borrowFacet.address, action: 0, functionSelectors: getSelectors(borrowFacet) },
    { facetAddress: liquidationFacet.address, action: 0, functionSelectors: getSelectors(liquidationFacet) },
    { facetAddress: configuratorFacet.address, action: 0, functionSelectors: getSelectors(configuratorFacet) },
    { facetAddress: viewFacet.address, action: 0, functionSelectors: getSelectors(viewFacet) },
  ];

  // Execute the diamond cut with init
  const diamondCut = (await ethers.getContractAt("DiamondCutFacet", diamond.address)) as DiamondCutFacet;
  const initCalldata = diamondInit.interface.encodeFunctionData("init", [adminAddress, oracleAddress]);
  const tx = await diamondCut.diamondCut(cut, diamondInit.address, initCalldata);
  await tx.wait();

  return {
    diamond,
    lendingPool: (await ethers.getContractAt("LendingPoolFacet", diamond.address)) as LendingPoolFacet,
    borrow: (await ethers.getContractAt("BorrowFacet", diamond.address)) as BorrowFacet,
    liquidation: (await ethers.getContractAt("LiquidationFacet", diamond.address)) as LiquidationFacet,
    configurator: (await ethers.getContractAt("ConfiguratorFacet", diamond.address)) as ConfiguratorFacet,
    view: (await ethers.getContractAt("ViewFacet", diamond.address)) as ViewFacet,
    owner: diamondCut,
  };
}
