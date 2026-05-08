// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TRHDiceGame} from "../src/examples/TRHGameRandomness.sol";
import {MockVRF} from "../src/mocks/MockVRF.sol";

contract TRHGameRandomnessTest is Test {
    MockVRF internal vrf;
    TRHDiceGame internal game;

    function setUp() public {
        vrf = new MockVRF();
        game = new TRHDiceGame(address(vrf));
    }

    function testConstructorDefaultsToPredeploy() public {
        TRHDiceGame defaultGame = new TRHDiceGame(address(0));
        assertEq(address(defaultGame.vrf()), defaultGame.ENSHRINED_VRF_PREDEPLOY());
    }

    function testRollUsesInjectedVRF() public {
        uint8 result = game.roll(6);
        assertGe(result, 1);
        assertLe(result, 6);
        assertEq(vrf.callCounter(), 1);
    }

    function testRollRejectsInvalidSides() public {
        vm.expectRevert(TRHDiceGame.InvalidDiceSides.selector);
        game.roll(1);
    }
}
