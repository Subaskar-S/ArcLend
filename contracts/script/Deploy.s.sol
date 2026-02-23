// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Script} from "forge-std/Script.sol";
import {LendingPool} from "../src/core/LendingPool.sol";
import {PriceOracle} from "../src/oracle/PriceOracle.sol";
import {
    DefaultInterestRateStrategy
} from "../src/interest/DefaultInterestRateStrategy.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Price Oracle
        PriceOracle oracle = new PriceOracle();

        // 2. Deploy Interest Rate Strategy
        // Optimal util 80%, Base 0%, Slope1 4%, Slope2 75%
        DefaultInterestRateStrategy strategy = new DefaultInterestRateStrategy(
            0.8e27, // 80%
            0, // 0%
            0.04e27, // 4%
            0.75e27 // 75%
        );

        // 3. Deploy Lending Pool Implementation
        LendingPool implementation = new LendingPool();

        // 4. Deploy Proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(LendingPool.initialize.selector, msg.sender)
        );

        LendingPool pool = LendingPool(address(proxy));

        // Output addresses
        console.log("PriceOracle:", address(oracle));
        console.log("InterestRateStrategy:", address(strategy));
        console.log("LendingPool Proxy:", address(pool));
        console.log("LendingPool Implementation:", address(implementation));

        vm.stopBroadcast();
    }
}
