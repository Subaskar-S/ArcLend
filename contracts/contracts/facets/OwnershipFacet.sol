// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {LibDiamond} from "../libraries/LibDiamond.sol";

/**
 * @title OwnershipFacet
 * @notice Manages contract ownership (required by EIP-173).
 */
contract OwnershipFacet {

    function transferOwnership(address _newOwner) external {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setContractOwner(_newOwner);
    }

    function owner() external view returns (address owner_) {
        owner_ = LibDiamond.contractOwner();
    }
}
