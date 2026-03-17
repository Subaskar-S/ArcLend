// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {LibDiamond} from "../libraries/LibDiamond.sol";

interface IDiamondLoupe {
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    function facets() external view returns (Facet[] memory facets_);
    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory facetFunctionSelectors_);
    function facetAddresses() external view returns (address[] memory facetAddresses_);
    function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_);
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @title DiamondLoupeFacet
 * @notice EIP-2535 introspection — exposes facet structure for explorers and tooling.
 */
contract DiamondLoupeFacet is IDiamondLoupe, IERC165 {
    function facets() external view override returns (Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 numFacets;
        // Count unique facets
        address[] memory seen = new address[](ds.selectors.length);
        uint256 seenCount;
        for (uint256 i; i < ds.selectors.length; i++) {
            address f = ds.facetAddressAndSelectorPosition[ds.selectors[i]].facetAddress;
            bool found;
            for (uint256 j; j < seenCount; j++) {
                if (seen[j] == f) { found = true; break; }
            }
            if (!found) { seen[seenCount++] = f; numFacets++; }
        }
        facets_ = new Facet[](numFacets);
        uint256[] memory counts = new uint256[](numFacets);
        for (uint256 i; i < ds.selectors.length; i++) {
            address f = ds.facetAddressAndSelectorPosition[ds.selectors[i]].facetAddress;
            for (uint256 j; j < numFacets; j++) {
                if (facets_[j].facetAddress == f || (facets_[j].facetAddress == address(0) && seen[j] == f)) {
                    if (facets_[j].facetAddress == address(0)) facets_[j].facetAddress = f;
                    counts[j]++;
                    break;
                }
            }
        }
        for (uint256 i; i < numFacets; i++) {
            facets_[i].functionSelectors = new bytes4[](counts[i]);
        }
        uint256[] memory idx = new uint256[](numFacets);
        for (uint256 i; i < ds.selectors.length; i++) {
            address f = ds.facetAddressAndSelectorPosition[ds.selectors[i]].facetAddress;
            for (uint256 j; j < numFacets; j++) {
                if (facets_[j].facetAddress == f) {
                    facets_[j].functionSelectors[idx[j]++] = ds.selectors[i];
                    break;
                }
            }
        }
    }

    function facetFunctionSelectors(address _facet) external view override returns (bytes4[] memory) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 count;
        for (uint256 i; i < ds.selectors.length; i++) {
            if (ds.facetAddressAndSelectorPosition[ds.selectors[i]].facetAddress == _facet) count++;
        }
        bytes4[] memory selectors = new bytes4[](count);
        uint256 idx;
        for (uint256 i; i < ds.selectors.length; i++) {
            if (ds.facetAddressAndSelectorPosition[ds.selectors[i]].facetAddress == _facet) {
                selectors[idx++] = ds.selectors[i];
            }
        }
        return selectors;
    }

    function facetAddresses() external view override returns (address[] memory) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        address[] memory tmp = new address[](ds.selectors.length);
        uint256 count;
        for (uint256 i; i < ds.selectors.length; i++) {
            address f = ds.facetAddressAndSelectorPosition[ds.selectors[i]].facetAddress;
            bool found;
            for (uint256 j; j < count; j++) { if (tmp[j] == f) { found = true; break; } }
            if (!found) tmp[count++] = f;
        }
        address[] memory result = new address[](count);
        for (uint256 i; i < count; i++) result[i] = tmp[i];
        return result;
    }

    function facetAddress(bytes4 _functionSelector) external view override returns (address) {
        return LibDiamond.diamondStorage().facetAddressAndSelectorPosition[_functionSelector].facetAddress;
    }

    function supportsInterface(bytes4 _interfaceId) external view override returns (bool) {
        return LibDiamond.diamondStorage().supportedInterfaces[_interfaceId];
    }
}
