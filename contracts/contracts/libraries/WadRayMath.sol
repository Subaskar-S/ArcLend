// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title WadRayMath
 * @notice Fixed-point math library for wad (1e18) and ray (1e27) precision.
 */
library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 0.5e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = 0.5e27;
    uint256 internal constant WAD_RAY_RATIO = 1e9;
    uint256 internal constant HALF_WAD_RAY_RATIO = 0.5e9;

    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        require(a <= (type(uint256).max - HALF_WAD) / b, "WMATH: WAD_MUL_OVERFLOW");
        return (a * b + HALF_WAD) / WAD;
    }

    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "WMATH: WAD_DIV_BY_ZERO");
        if (a == 0) return 0;
        require(a <= (type(uint256).max - b / 2) / WAD, "WMATH: WAD_DIV_OVERFLOW");
        return (a * WAD + b / 2) / b;
    }

    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        require(a <= (type(uint256).max - HALF_RAY) / b, "WMATH: RAY_MUL_OVERFLOW");
        return (a * b + HALF_RAY) / RAY;
    }

    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "WMATH: RAY_DIV_BY_ZERO");
        if (a == 0) return 0;
        require(a <= (type(uint256).max - b / 2) / RAY, "WMATH: RAY_DIV_OVERFLOW");
        return (a * RAY + b / 2) / b;
    }

    function rayMulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        require(a <= (type(uint256).max - RAY + 1) / b, "WMATH: RAY_MUL_UP_OVERFLOW");
        return (a * b + RAY - 1) / RAY;
    }

    function rayDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "WMATH: RAY_DIV_UP_BY_ZERO");
        if (a == 0) return 0;
        require(a <= (type(uint256).max - b + 1) / RAY, "WMATH: RAY_DIV_UP_OVERFLOW");
        return (a * RAY + b - 1) / b;
    }

    function rayToWad(uint256 a) internal pure returns (uint256) {
        uint256 halfratio = HALF_WAD_RAY_RATIO;
        uint256 result = halfratio + a;
        require(result >= halfratio, "WMATH: RAY_TO_WAD_OVERFLOW");
        return result / WAD_RAY_RATIO;
    }

    function wadToRay(uint256 a) internal pure returns (uint256) {
        uint256 result = a * WAD_RAY_RATIO;
        require(result / WAD_RAY_RATIO == a, "WMATH: WAD_TO_RAY_OVERFLOW");
        return result;
    }
}
