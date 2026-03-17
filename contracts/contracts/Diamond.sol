// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {LibDiamond} from "./libraries/LibDiamond.sol";

/**
 * @title Diamond
 * @notice EIP-2535 Diamond proxy contract — the entry point for the entire protocol.
 * @dev All function calls are delegated to the appropriate facet via the fallback function.
 *      Facets are added/replaced/removed by calling DiamondCutFacet.
 */
contract Diamond {
    constructor(address _contractOwner, address _diamondCutFacet) payable {
        LibDiamond.setContractOwner(_contractOwner);

        // Add the diamondCut external function from the diamondCutFacet
        LibDiamond.FacetCut[] memory cut = new LibDiamond.FacetCut[](1);
        bytes4[] memory functionSelectors = new bytes4[](1);
        functionSelectors[0] = bytes4(
            keccak256("diamondCut((address,uint8,bytes4[])[],address,bytes)")
        );
        cut[0] = LibDiamond.FacetCut({
            facetAddress: _diamondCutFacet,
            action: LibDiamond.FacetCutAction.Add,
            functionSelectors: functionSelectors
        });
        LibDiamond.diamondCut(cut, address(0), "");
    }

    // ─── Fallback: Route all calls to the correct facet ──────────────────
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds;
        bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
        address facet = ds.facetAddressAndSelectorPosition[msg.sig].facetAddress;
        require(facet != address(0), "Diamond: Function does not exist");
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {}
}
