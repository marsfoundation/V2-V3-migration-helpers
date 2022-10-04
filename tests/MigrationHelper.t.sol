// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';

import {AaveV2Polygon} from 'aave-address-book/AaveV2Polygon.sol';
import {AaveV3Polygon} from 'aave-address-book/AaveV3Polygon.sol';

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {DataTypes, IAaveProtocolDataProvider} from 'aave-address-book/AaveV2.sol';

import {MigrationHelper, IMigrationHelper, IERC20WithPermit} from '../src/contracts/MigrationHelper.sol';

contract MigrationHelperTest is Test {
  IAaveProtocolDataProvider public v2DataProvider;
  MigrationHelper public migrationHelper;

  address[] public usersSimple;
  address[] public v2Reserves;

  function setUp() public {
    // TODO: set fixed block number
    vm.createSelectFork(vm.rpcUrl('polygon'));
    migrationHelper = new MigrationHelper(
      AaveV3Polygon.POOL_ADDRESSES_PROVIDER,
      AaveV2Polygon.POOL
    );

    v2DataProvider = AaveV2Polygon.AAVE_PROTOCOL_DATA_PROVIDER;
    v2Reserves = migrationHelper.V2_POOL().getReservesList();

    usersSimple = new address[](17);
    usersSimple[0] = 0x5FFAcBDaA5754224105879c03392ef9FE6ae0c17;
    usersSimple[1] = 0x5d3f81Ad171616571BF3119a3120E392B914Fd7C;
    usersSimple[2] = 0x07F294e84a9574f657A473f94A242F1FdFAFB823;
    usersSimple[3] = 0x7734280A4337F37Fbf4651073Db7c28C80B339e9;
    usersSimple[4] = 0x000000003853FCeDcd0355feC98cA3192833F00b;
    usersSimple[5] = 0xbeC1101FF3f3474A3789Bb18A88117C169178d9F;
    usersSimple[6] = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    usersSimple[7] = 0x004C572659319871bE9D4ab337fB3Df6237979D7;
    usersSimple[8] = 0x0134af0F5cf7C32128231deA65B52Bb892780bae;
    usersSimple[9] = 0x0040a8fbD83A82c0742923C6802C3d9a22128d1c;
    usersSimple[10] = 0x00F63722233F5e19010e5daF208472A8F27D304B;
    usersSimple[11] = 0x114558d984bb24FDDa0CD279Ffd5F073F2d44F49;
    usersSimple[12] = 0x17B23Be942458E6EfC17F000976A490EC428f49A;
    usersSimple[13] = 0x7c0714297f15599E7430332FE45e45887d7Da341;
    usersSimple[14] = 0x1776Fd7CCf75C889d62Cd03B5116342EB13268Bc;
    usersSimple[15] = 0x53498839353845a30745b56a22524Df934F746dE;
    usersSimple[16] = 0x3126ffE1334d892e0c53d8e2Fc83a605DcDCf037;
  }

  function testCacheATokens() public {
    for (uint256 i = 0; i < v2Reserves.length; i++) {
      DataTypes.ReserveData memory reserveData = migrationHelper
        .V2_POOL()
        .getReserveData(v2Reserves[i]);
      assertEq(
        address(migrationHelper.aTokens(v2Reserves[i])),
        reserveData.aTokenAddress
      );

      uint256 allowanceToPoolV2 = IERC20(v2Reserves[i]).allowance(
        address(migrationHelper),
        address(migrationHelper.V2_POOL())
      );
      assertEq(allowanceToPoolV2, type(uint256).max);

      uint256 allowanceToPool = IERC20(v2Reserves[i]).allowance(
        address(migrationHelper),
        address(migrationHelper.POOL())
      );
      assertEq(allowanceToPool, type(uint256).max);
    }
  }

  function testMigrationNoBorrowNoPermit() public {
    address[] memory suppliedPositions;
    IMigrationHelper.RepayInput[] memory borrowedPositions;

    for (uint256 i = 0; i < usersSimple.length; i++) {
      // get positions
      (suppliedPositions, borrowedPositions) = _getV2UserPosition(
        usersSimple[i]
      );
      require(
        borrowedPositions.length == 0 && suppliedPositions.length != 0,
        'BAD_USER_FOR_THIS_TEST'
      );

      vm.startPrank(usersSimple[i]);
      // TODO: add test with permit
      // approve aTokens to helper
      for (uint256 j = 0; j < suppliedPositions.length; j++) {
        migrationHelper.aTokens(suppliedPositions[j]).approve(
          address(migrationHelper),
          type(uint256).max
        );
      }
      vm.stopPrank();

      migrationHelper.migrationNoBorrow(
        usersSimple[i],
        suppliedPositions,
        new IMigrationHelper.PermitInput[](0)
      );
    }
  }

  function _getV2UserPosition(address user)
    internal
    view
    returns (address[] memory, IMigrationHelper.RepayInput[] memory)
  {
    uint256 numberOfSupplied;
    uint256 numberOfBorrowed;
    address[] memory suppliedPositions = new address[](v2Reserves.length);
    IMigrationHelper.RepayInput[]
      memory borrowedPositions = new IMigrationHelper.RepayInput[](
        v2Reserves.length * 2
      );
    for (uint256 i = 0; i < v2Reserves.length; i++) {
      (
        uint256 currentATokenBalance,
        uint256 currentStableDebt,
        uint256 currentVariableDebt,
        ,
        ,
        ,
        ,
        ,

      ) = v2DataProvider.getUserReserveData(v2Reserves[i], user);
      if (currentATokenBalance != 0) {
        suppliedPositions[numberOfSupplied] = v2Reserves[i];
        numberOfSupplied++;
      }
      if (currentStableDebt != 0) {
        borrowedPositions[numberOfBorrowed] = IMigrationHelper.RepayInput({
          asset: v2Reserves[i],
          amount: currentStableDebt,
          rateMode: 1
        });
        numberOfBorrowed++;
      }
      if (currentVariableDebt != 0) {
        borrowedPositions[numberOfBorrowed] = IMigrationHelper.RepayInput({
          asset: v2Reserves[i],
          amount: currentVariableDebt,
          rateMode: 2
        });
        numberOfBorrowed++;
      }
    }
    assembly {
      mstore(suppliedPositions, numberOfSupplied)
      mstore(borrowedPositions, numberOfBorrowed)
    }

    return (suppliedPositions, borrowedPositions);
  }
}
