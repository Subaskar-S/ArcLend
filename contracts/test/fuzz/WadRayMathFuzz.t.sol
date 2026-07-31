// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {WadRayMath} from "../../contracts/libraries/WadRayMath.sol";
import {PercentageMath} from "../../contracts/libraries/PercentageMath.sol";

/**
 * @title WadRayMathFuzzTest
 * @notice Fuzz tests for WadRayMath and PercentageMath libraries.
 *
 * Wrapper contracts are used for revert tests because Foundry's vm.expectRevert
 * requires an external call — library functions cannot be called externally directly.
 */
contract WadRayMathFuzzTest is Test {
    uint256 internal constant WAD           = 1e18;
    uint256 internal constant HALF_WAD      = 0.5e18;
    uint256 internal constant RAY           = 1e27;
    uint256 internal constant HALF_RAY      = 0.5e27;
    uint256 internal constant WAD_RAY_RATIO = 1e9;

    WadMulWrapper   internal wadMulWrapper;
    WadDivWrapper   internal wadDivWrapper;
    RayMulWrapper   internal rayMulWrapper;
    RayDivWrapper   internal rayDivWrapper;
    WadToRayWrapper internal wadToRayWrapper;

    function setUp() public {
        wadMulWrapper   = new WadMulWrapper();
        wadDivWrapper   = new WadDivWrapper();
        rayMulWrapper   = new RayMulWrapper();
        rayDivWrapper   = new RayDivWrapper();
        wadToRayWrapper = new WadToRayWrapper();
    }

    // ─── wadMul ──────────────────────────────────────────────────────────────

    function testFuzz_WadMul_ResultMatchesFormula(uint256 a, uint256 b) public pure {
        vm.assume(a == 0 || b <= (type(uint256).max - HALF_WAD) / a);
        assertEq(WadRayMath.wadMul(a, b), (a * b + HALF_WAD) / WAD);
    }

    function testFuzz_WadMul_Commutative(uint256 a, uint256 b) public pure {
        vm.assume(a == 0 || b <= (type(uint256).max - HALF_WAD) / a);
        assertEq(WadRayMath.wadMul(a, b), WadRayMath.wadMul(b, a));
    }

    function testFuzz_WadMul_Zero(uint256 a) public pure {
        assertEq(WadRayMath.wadMul(a, 0), 0);
        assertEq(WadRayMath.wadMul(0, a), 0);
    }

    function testFuzz_WadMul_Identity(uint256 a) public pure {
        vm.assume(a <= (type(uint256).max - HALF_WAD) / WAD);
        assertApproxEqAbs(WadRayMath.wadMul(a, WAD), a, 1);
    }

    function testFuzz_WadMul_Overflow(uint256 a, uint256 b) public {
        vm.assume(a > 0 && b > 0);
        vm.assume(b > (type(uint256).max - HALF_WAD) / a);
        vm.expectRevert();
        wadMulWrapper.doWadMul(a, b);
    }

    // ─── wadDiv ──────────────────────────────────────────────────────────────

    function testFuzz_WadDiv_ResultMatchesFormula(uint256 a, uint256 b) public pure {
        vm.assume(b > 0);
        vm.assume(a == 0 || a <= (type(uint256).max - b / 2) / WAD);
        assertEq(WadRayMath.wadDiv(a, b), (a * WAD + b / 2) / b);
    }

    function testFuzz_WadDiv_Zero(uint256 b) public pure {
        vm.assume(b > 0);
        assertEq(WadRayMath.wadDiv(0, b), 0);
    }

    function testFuzz_WadDiv_ByZero(uint256 a) public {
        vm.expectRevert();
        wadDivWrapper.doWadDiv(a, 0);
    }

    function testFuzz_WadDiv_Identity(uint256 a) public pure {
        vm.assume(a <= (type(uint256).max - WAD / 2) / WAD);
        assertApproxEqAbs(WadRayMath.wadDiv(a, WAD), a, 1);
    }

    function testFuzz_WadMulDiv_Roundtrip(uint256 a, uint256 b) public pure {
        vm.assume(b >= 1e6 && a >= 1e6 && a < 1e24 && b < 1e24);
        vm.assume(a <= (type(uint256).max - HALF_WAD) / b);
        uint256 mulResult = WadRayMath.wadMul(a, b);
        vm.assume(mulResult >= 1e6); // ensure no zero result from rounding
        vm.assume(mulResult <= (type(uint256).max - b / 2) / WAD);
        // Allow 0.001% relative error for double rounding
        assertApproxEqRel(WadRayMath.wadDiv(mulResult, b), a, 1e13);
    }

    // ─── rayMul ──────────────────────────────────────────────────────────────

    function testFuzz_RayMul_ResultMatchesFormula(uint256 a, uint256 b) public pure {
        vm.assume(a == 0 || b <= (type(uint256).max - HALF_RAY) / a);
        assertEq(WadRayMath.rayMul(a, b), (a * b + HALF_RAY) / RAY);
    }

    function testFuzz_RayMul_Zero(uint256 a) public pure {
        assertEq(WadRayMath.rayMul(a, 0), 0);
        assertEq(WadRayMath.rayMul(0, a), 0);
    }

    function testFuzz_RayMul_Identity(uint256 a) public pure {
        vm.assume(a <= (type(uint256).max - HALF_RAY) / RAY);
        assertApproxEqAbs(WadRayMath.rayMul(a, RAY), a, 1);
    }

    function testFuzz_RayMul_Overflow(uint256 a, uint256 b) public {
        vm.assume(a > 0 && b > 0);
        vm.assume(b > (type(uint256).max - HALF_RAY) / a);
        vm.expectRevert();
        rayMulWrapper.doRayMul(a, b);
    }

    // ─── rayDiv ──────────────────────────────────────────────────────────────

    function testFuzz_RayDiv_ResultMatchesFormula(uint256 a, uint256 b) public pure {
        vm.assume(b > 0);
        vm.assume(a == 0 || a <= (type(uint256).max - b / 2) / RAY);
        assertEq(WadRayMath.rayDiv(a, b), (a * RAY + b / 2) / b);
    }

    function testFuzz_RayDiv_Zero(uint256 b) public pure {
        vm.assume(b > 0);
        assertEq(WadRayMath.rayDiv(0, b), 0);
    }

    function testFuzz_RayDiv_ByZero(uint256 a) public {
        vm.expectRevert();
        rayDivWrapper.doRayDiv(a, 0);
    }

    /// @notice Concrete verification: rayMul(a, RAY) == a (identity property)
    function testFuzz_RayMul_RayIdentity(uint256 a) public pure {
        // rayMul(a, RAY) = (a * RAY + HALF_RAY) / RAY = a + rounding
        vm.assume(a <= (type(uint256).max - HALF_RAY) / RAY);
        assertApproxEqAbs(WadRayMath.rayMul(a, RAY), a, 1);
    }

    /// @notice Concrete verification: rayDiv(a, RAY) == a (identity property)
    function testFuzz_RayDiv_RayIdentity(uint256 a) public pure {
        // rayDiv(a, RAY) = (a * RAY + HALF_RAY) / RAY = a + rounding
        vm.assume(a <= (type(uint256).max - HALF_RAY) / RAY);
        assertApproxEqAbs(WadRayMath.rayDiv(a, RAY), a, 1);
    }

    // ─── Conversions ─────────────────────────────────────────────────────────

    function testFuzz_WadToRay(uint256 a) public pure {
        vm.assume(a <= type(uint256).max / WAD_RAY_RATIO);
        assertEq(WadRayMath.wadToRay(a), a * WAD_RAY_RATIO);
    }

    function testFuzz_WadToRay_Overflow(uint256 a) public {
        vm.assume(a > type(uint256).max / WAD_RAY_RATIO);
        vm.expectRevert();
        wadToRayWrapper.doWadToRay(a);
    }

    function testFuzz_RayToWad(uint256 a) public pure {
        // Guard: avoid the HALF_WAD_RAY_RATIO + a overflow inside rayToWad
        vm.assume(a <= type(uint256).max - 500000000); // subtract HALF_WAD_RAY_RATIO
        uint256 c = WadRayMath.rayToWad(a);
        uint256 expected = a / WAD_RAY_RATIO;
        if (a % WAD_RAY_RATIO >= WAD_RAY_RATIO / 2) expected++;
        assertEq(c, expected);
    }

    function testFuzz_WadToRay_RayToWad_Roundtrip(uint256 a) public pure {
        vm.assume(a <= type(uint256).max / WAD_RAY_RATIO);
        assertEq(WadRayMath.rayToWad(WadRayMath.wadToRay(a)), a);
    }

    // ─── PercentageMath ───────────────────────────────────────────────────────

    function testFuzz_PercentMul_Zero(uint256 a) public pure {
        assertEq(PercentageMath.percentMul(0, a), 0);
        assertEq(PercentageMath.percentMul(a, 0), 0);
    }

    function testFuzz_PercentMul_FullBps(uint256 a) public pure {
        vm.assume(a <= (type(uint256).max - 5000) / 10000);
        assertApproxEqAbs(PercentageMath.percentMul(a, 10000), a, 1);
    }

    function testFuzz_PercentMulDiv_Roundtrip(uint256 a, uint16 bps) public pure {
        vm.assume(bps >= 100 && bps <= 20000);
        vm.assume(a >= 1000 && a <= (type(uint256).max - 5000) / uint256(bps));
        uint256 mulResult = PercentageMath.percentMul(a, bps);
        uint256 halfBps = uint256(bps) / 2;
        vm.assume(mulResult > 0 && mulResult <= (type(uint256).max - halfBps) / 10000);
        uint256 divResult = PercentageMath.percentDiv(mulResult, bps);
        // Two independent rounding operations each add at most PERCENTAGE_FACTOR/2 error.
        // Total error is bounded: |result - a| <= 2 * 5000 / bps
        uint256 maxError = 2 * 5000 / uint256(bps) + 1;
        assertApproxEqAbs(divResult, a, maxError);
    }
}

// ─── Wrapper contracts for revert testing ─────────────────────────────────────

contract WadMulWrapper {
    function doWadMul(uint256 a, uint256 b) external pure returns (uint256) {
        return WadRayMath.wadMul(a, b);
    }
}

contract WadDivWrapper {
    function doWadDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return WadRayMath.wadDiv(a, b);
    }
}

contract RayMulWrapper {
    function doRayMul(uint256 a, uint256 b) external pure returns (uint256) {
        return WadRayMath.rayMul(a, b);
    }
}

contract RayDivWrapper {
    function doRayDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return WadRayMath.rayDiv(a, b);
    }
}

contract WadToRayWrapper {
    function doWadToRay(uint256 a) external pure returns (uint256) {
        return WadRayMath.wadToRay(a);
    }
}
