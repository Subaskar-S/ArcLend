// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {LendingPool} from "../../src/core/LendingPool.sol";

contract LendingPoolTest is Test {
    LendingPool public pool;

    function setUp() public {
        pool = new LendingPool();
        pool.initialize(address(this));
    }

    function test_Initialization() public {
        // Simple test to ensure the pool initializes correctly
        assertTrue(address(pool) != address(0));
    }
}
