// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {WadRayMath} from "../../src/libraries/WadRayMath.sol";

contract WadRayMathFuzzTest is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 0.5e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = 0.5e27;
    uint256 internal constant WAD_RAY_RATIO = 1e9;

    function testFuzz_WadMul(uint256 a, uint256 b) public {
        vm.assume(a == 0 || b <= type(uint256).max / a);

        uint256 c = WadRayMath.wadMul(a, b);

        // Validation logic for WadMul
        uint256 expected = (a * b + HALF_WAD) / WAD;
        assertEq(c, expected);
    }

    function testFuzz_RayMul(uint256 a, uint256 b) public {
        vm.assume(a == 0 || b <= type(uint256).max / a);

        uint256 c = WadRayMath.rayMul(a, b);

        // Validation logic for RayMul
        uint256 expected = (a * b + HALF_RAY) / RAY;
        assertEq(c, expected);
    }

    function testFuzz_WadToRay(uint256 a) public {
        vm.assume(a <= type(uint256).max / WAD_RAY_RATIO);
        uint256 c = WadRayMath.wadToRay(a);
        assertEq(c, a * WAD_RAY_RATIO);
    }

    function testFuzz_RayToWad(uint256 a) public {
        uint256 c = WadRayMath.rayToWad(a);
        uint256 expected = a / WAD_RAY_RATIO;
        uint256 remainder = a % WAD_RAY_RATIO;
        if (remainder >= WAD_RAY_RATIO / 2) {
            expected++;
        }
        assertEq(c, expected);
    }
}
