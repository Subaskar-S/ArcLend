// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {LibDiamond} from "../libraries/LibDiamond.sol";

/**
 * @title DiamondCutFacet
 * @notice Implements EIP-2535 diamondCut function.
 * @dev Restricted to the contract owner.
 */
contract DiamondCutFacet {
    /**
     * @notice Add/replace/remove any number of functions and optionally execute
     *         a function with delegatecall.
     * @param _diamondCut Array of FacetCut structs
     * @param _init The address of the contract or facet to execute _calldata
     * @param _calldata Function call, including function selector and arguments
     */
    function diamondCut(
        LibDiamond.FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
