/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity >0.8.10;

import "./fixtures/ArcadiaVaultsFixture.f.sol";

contract FloorERC1155PricingModuleTest is DeployArcadiaVaults {
    using stdStorage for StdStorage;

    //this is a before
    constructor() DeployArcadiaVaults() {}

    //this is a before each
    function setUp() public {
        vm.startPrank(creatorAddress);
        mainRegistry = new MainRegistry(
            MainRegistry.BaseCurrencyInformation({
                baseCurrencyToUsdOracleUnit: 0,
                assetAddress: 0x0000000000000000000000000000000000000000,
                baseCurrencyToUsdOracle: 0x0000000000000000000000000000000000000000,
                baseCurrencyLabel: "USD",
                baseCurrencyUnitCorrection: uint64(10**(18 - Constants.usdDecimals))
            })
        );
        mainRegistry.addBaseCurrency(
            MainRegistry.BaseCurrencyInformation({
                baseCurrencyToUsdOracleUnit: uint64(10 ** Constants.oracleDaiToUsdDecimals),
                assetAddress: address(dai),
                baseCurrencyToUsdOracle: address(oracleDaiToUsd),
                baseCurrencyLabel: "DAI",
                baseCurrencyUnitCorrection: uint64(10 ** (18 - Constants.daiDecimals))
            })
        );
        mainRegistry.addBaseCurrency(
            MainRegistry.BaseCurrencyInformation({
                baseCurrencyToUsdOracleUnit: uint64(10 ** Constants.oracleEthToUsdDecimals),
                assetAddress: address(eth),
                baseCurrencyToUsdOracle: address(oracleEthToUsd),
                baseCurrencyLabel: "ETH",
                baseCurrencyUnitCorrection: uint64(10 ** (18 - Constants.ethDecimals))
            })
        );

        floorERC1155PricingModule = new FloorERC1155PricingModule(
            address(mainRegistry),
            address(oracleHub)
        );
        mainRegistry.addPricingModule(address(floorERC1155PricingModule));
        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                        ASSET MANAGEMENT
    ///////////////////////////////////////////////////////////////*/

    function testRevert_addAsset_NonOwner(address unprivilegedAddress_) public {
        // Given: unprivilegedAddress_ is not creatorAddress
        vm.assume(unprivilegedAddress_ != creatorAddress);
        vm.startPrank(unprivilegedAddress_);
        // When: unprivilegedAddress_ calls addAsset

        // Then: addAsset should revert with "Ownable: caller is not the owner"
        vm.expectRevert("Ownable: caller is not the owner");
        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, emptyRiskVarInput);

        vm.stopPrank();
    }

    function testRevert_addAsset_OverwriteExistingAsset() public {
        // Given: All necessary contracts deployed on setup
        vm.startPrank(creatorAddress);
        // When: creatorAddress calls addAsset twice
        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, emptyRiskVarInput);
        vm.expectRevert("PM1155_AA: already added");
        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, emptyRiskVarInput);
        vm.stopPrank();

        // Then: inPricingModule for address(interleave) should return true
        assertTrue(floorERC1155PricingModule.inPricingModule(address(interleave)));
        assertEq(floorERC1155PricingModule.assetsInPricingModule(0), address(interleave));
        (uint256 id, address[] memory oracles) = floorERC1155PricingModule.getAssetInformation(address(interleave));
        assertEq(id, 1);
        for (uint256 i; i < oracleInterleaveToEthEthToUsd.length; i++) {
            assertEq(oracles[i], oracleInterleaveToEthEthToUsd[i]);
        }
        assertTrue(floorERC1155PricingModule.isWhiteListed(address(interleave), 0));
    }

    function testSuccess_addAsset_EmptyListRiskVariables() public {
        // Given: All necessary contracts deployed on setup
        vm.startPrank(creatorAddress);
        // When: creatorAddress calls addAsset with empty list credit ratings
        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, emptyRiskVarInput);
        vm.stopPrank();

        // Then: inPricingModule for address(interleave) should return true
        assertTrue(floorERC1155PricingModule.inPricingModule(address(interleave)));
    }

    function testSuccess_addAsset_NonFullListRiskVariables() public {
        vm.startPrank(creatorAddress);
        // Given: collateralFactors index 0 is DEFAULT_COLLATERAL_FACTOR, liquidationThresholds index 0 is DEFAULT_LIQUIDATION_THRESHOLD
        PricingModule.RiskVarInput[] memory riskVars_ = new PricingModule.RiskVarInput[](1);
        riskVars_[0] = PricingModule.RiskVarInput({
            baseCurrency: 0,
            asset: address(0),
            collateralFactor: collFactor,
            liquidationThreshold: liqTresh
        });

        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, riskVars_);
        vm.stopPrank();

        assertTrue(floorERC1155PricingModule.inPricingModule(address(interleave)));
    }

    function testSuccess_addAsset_FullListRiskVariables() public {
        // Given: collateralFactors index 0 and 1 is DEFAULT_COLLATERAL_FACTOR, liquidationThresholds index 0 and 1 is DEFAULT_LIQUIDATION_THRESHOLD
        vm.startPrank(creatorAddress);
        // When: creatorAddress calls addAsset with full list credit ratings
        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, riskVars);
        vm.stopPrank();

        // Then: inPricingModule for address(interleave) should return true
        assertTrue(floorERC1155PricingModule.inPricingModule(address(interleave)));
    }

    function testRevert_setOracles_NonOwner(address unprivilegedAddress_, address asset) public {
        vm.assume(unprivilegedAddress_ != creatorAddress);

        vm.startPrank(unprivilegedAddress_);
        vm.expectRevert("Ownable: caller is not the owner");
        floorERC1155PricingModule.setOracles(asset, new address[](0));
        vm.stopPrank();
    }

    function testRevert_setOracles_AssetUnknown(address asset) public {
        vm.startPrank(creatorAddress);
        vm.expectRevert("PM1155_SO: asset unknown");
        floorERC1155PricingModule.setOracles(asset, new address[](0));
        vm.stopPrank();
    }

    function testSuccess_setOracles() public {
        stdstore.target(address(floorERC1155PricingModule)).sig(floorERC1155PricingModule.inPricingModule.selector)
            .with_key(address(interleave)).checked_write(true);

        vm.prank(creatorAddress);
        floorERC1155PricingModule.setOracles(address(interleave), oracleInterleaveToEthEthToUsd);

        (, address[] memory oracles) = floorERC1155PricingModule.getAssetInformation(address(interleave));
        for (uint256 i; i < oracleInterleaveToEthEthToUsd.length; i++) {
            assertEq(oracles[i], oracleInterleaveToEthEthToUsd[i]);
        }
    }

    /*///////////////////////////////////////////////////////////////
                        WHITE LIST MANAGEMENT
    ///////////////////////////////////////////////////////////////*/

    function testSuccess_isWhiteListed_Positive() public {
        // Given: All necessary contracts deployed on setup
        vm.startPrank(creatorAddress);
        // When: creatorAddress calls addAsset
        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, emptyRiskVarInput);
        vm.stopPrank();

        // Then: isWhiteListed for address(interleave) should return true
        assertTrue(floorERC1155PricingModule.isWhiteListed(address(interleave), 1));
    }

    function testSuccess_isWhiteListed_NegativeWrongAddress(address randomAsset) public {
        // Given: All necessary contracts deployed on setup
        // When: input is randomAsset

        // Then: isWhiteListed for randomAsset should return false
        assertTrue(!floorERC1155PricingModule.isWhiteListed(randomAsset, 1));
    }

    function testSuccess_isWhiteListed_NegativeIdOutsideRange(uint256 id) public {
        // Given: id is not 1
        vm.assume(id != 1);
        vm.startPrank(creatorAddress);
        // When: creatorAddress calls addAsset
        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, emptyRiskVarInput);
        vm.stopPrank();

        // Then: isWhiteListed for address(interlave) should return false
        assertTrue(!floorERC1155PricingModule.isWhiteListed(address(interleave), id));
    }

    /*///////////////////////////////////////////////////////////////
                          PRICING LOGIC
    ///////////////////////////////////////////////////////////////*/

    function testSuccess_getValue_ReturnUsdValueWhenBaseCurrencyIsUsd(uint128 amountInterleave) public {
        //Does not test on overflow, test to check if function correctly returns value in BaseCurrency
        vm.startPrank(creatorAddress);
        // Given: creatorAddress calls addAsset, expectedValueInBaseCurrency is zero
        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, emptyRiskVarInput);
        vm.stopPrank();

        uint256 expectedValueInUsd = (amountInterleave * rateInterleaveToEth * rateEthToUsd * Constants.WAD)
            / 10 ** (Constants.oracleInterleaveToEthDecimals + Constants.oracleEthToUsdDecimals);
        uint256 expectedValueInBaseCurrency = 0;

        PricingModule.GetValueInput memory getValueInput = PricingModule.GetValueInput({
            asset: address(interleave),
            assetId: 1,
            assetAmount: amountInterleave,
            baseCurrency: uint8(Constants.UsdBaseCurrency)
        });
        // When: getValue called
        (uint256 actualValueInUsd, uint256 actualValueInBaseCurrency,,) =
            floorERC1155PricingModule.getValue(getValueInput);

        // Then: actualValueInUsd should be equal to expectedValueInUsd, actualValueInBaseCurrency should be equal to expectedValueInBaseCurrency
        assertEq(actualValueInUsd, expectedValueInUsd);
        assertEq(actualValueInBaseCurrency, expectedValueInBaseCurrency);
    }

    function testSuccess_getValue_returnBaseCurrencyValueWhenBaseCurrencyIsNotUsd(uint128 amountInterleave) public {
        //Does not test on overflow, test to check if function correctly returns value in BaseCurrency
        vm.startPrank(creatorAddress);
        // Given: creatorAddress calls addAsset, expectedValueInUsd is zero
        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, emptyRiskVarInput);
        vm.stopPrank();

        uint256 expectedValueInUsd = 0;
        uint256 expectedValueInBaseCurrency =
            (amountInterleave * rateInterleaveToEth * Constants.WAD) / 10 ** (Constants.oracleInterleaveToEthDecimals);

        PricingModule.GetValueInput memory getValueInput = PricingModule.GetValueInput({
            asset: address(interleave),
            assetId: 1,
            assetAmount: amountInterleave,
            baseCurrency: uint8(Constants.EthBaseCurrency)
        });
        // When: getValue called
        (uint256 actualValueInUsd, uint256 actualValueInBaseCurrency,,) =
            floorERC1155PricingModule.getValue(getValueInput);

        // Then: actualValueInUsd should be equal to expectedValueInUsd, actualValueInBaseCurrency should be equal to expectedValueInBaseCurrency
        assertEq(actualValueInUsd, expectedValueInUsd);
        assertEq(actualValueInBaseCurrency, expectedValueInBaseCurrency);
    }

    function testSuccess_getValue_ReturnUsdValueWhenBaseCurrencyIsNotUsd(uint128 amountInterleave) public {
        //Does not test on overflow, test to check if function correctly returns value in BaseCurrency
        vm.startPrank(creatorAddress);
        // Given: creatorAddress calls addAsset, expectedValueInBaseCurrency is zero
        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, emptyRiskVarInput);
        vm.stopPrank();

        uint256 expectedValueInUsd = (amountInterleave * rateInterleaveToEth * rateEthToUsd * Constants.WAD)
            / 10 ** (Constants.oracleInterleaveToEthDecimals + Constants.oracleEthToUsdDecimals);
        uint256 expectedValueInBaseCurrency = 0;

        PricingModule.GetValueInput memory getValueInput = PricingModule.GetValueInput({
            asset: address(interleave),
            assetId: 1,
            assetAmount: amountInterleave,
            baseCurrency: uint8(Constants.DaiBaseCurrency)
        });
        // When: getValue called
        (uint256 actualValueInUsd, uint256 actualValueInBaseCurrency,,) =
            floorERC1155PricingModule.getValue(getValueInput);

        // Then: actualValueInUsd should be equal to expectedValueInUsd, actualValueInBaseCurrency should be equal to expectedValueInBaseCurrency
        assertEq(actualValueInUsd, expectedValueInUsd);
        assertEq(actualValueInBaseCurrency, expectedValueInBaseCurrency);
    }

    function testSuccess_getValue_ReturnValue(uint256 amountInterleave, uint256 rateInterleaveToEthNew) public {
        // Given: rateInterleaveToEthNew is lower than equal to max int256 value and max uint256 value divided by Constants.WAD
        vm.assume(rateInterleaveToEthNew <= uint256(type(int256).max));
        vm.assume(rateInterleaveToEthNew <= type(uint256).max / Constants.WAD);

        if (rateInterleaveToEthNew == 0) {
            vm.assume(uint256(amountInterleave) <= type(uint256).max / Constants.WAD);
        } else {
            vm.assume(
                uint256(amountInterleave)
                    <= type(uint256).max / Constants.WAD * 10 ** Constants.oracleInterleaveToEthDecimals
                        / uint256(rateInterleaveToEthNew)
            );
        }

        vm.startPrank(oracleOwner);
        oracleInterleaveToEth.transmit(int256(rateInterleaveToEthNew));
        vm.stopPrank();

        vm.startPrank(creatorAddress);
        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, emptyRiskVarInput);
        vm.stopPrank();

        uint256 expectedValueInUsd = 0;
        uint256 expectedValueInBaseCurrency = (
            (rateInterleaveToEthNew * Constants.WAD) / 10 ** Constants.oracleInterleaveToEthDecimals
        ) * amountInterleave;

        PricingModule.GetValueInput memory getValueInput = PricingModule.GetValueInput({
            asset: address(interleave),
            assetId: 1,
            assetAmount: amountInterleave,
            baseCurrency: uint8(Constants.EthBaseCurrency)
        });
        // When: getValue called
        (uint256 actualValueInUsd, uint256 actualValueInBaseCurrency,,) =
            floorERC1155PricingModule.getValue(getValueInput);

        // Then: actualValueInUsd should be equal to expectedValueInUsd, actualValueInBaseCurrency should be equal to expectedValueInBaseCurrency
        assertEq(actualValueInUsd, expectedValueInUsd);
        assertEq(actualValueInBaseCurrency, expectedValueInBaseCurrency);
    }

    function testRevert_getValue_Overflow(uint256 amountInterleave, uint256 rateInterleaveToEthNew) public {
        // Given: rateInterleaveToEthNew is lower than equal to max int256 value and max uint256 value divided by Constants.WAD and bigger than zero
        vm.assume(rateInterleaveToEthNew <= uint256(type(int256).max));
        vm.assume(rateInterleaveToEthNew <= type(uint256).max / Constants.WAD);
        vm.assume(rateInterleaveToEthNew > 0);

        vm.assume(
            amountInterleave
                > type(uint256).max / Constants.WAD * 10 ** Constants.oracleInterleaveToEthDecimals
                    / uint256(rateInterleaveToEthNew)
        );

        vm.startPrank(oracleOwner);
        oracleInterleaveToEth.transmit(int256(rateInterleaveToEthNew));
        vm.stopPrank();

        vm.startPrank(creatorAddress);
        floorERC1155PricingModule.addAsset(address(interleave), 1, oracleInterleaveToEthEthToUsd, emptyRiskVarInput);
        vm.stopPrank();

        PricingModule.GetValueInput memory getValueInput = PricingModule.GetValueInput({
            asset: address(interleave),
            assetId: 1,
            assetAmount: amountInterleave,
            baseCurrency: uint8(Constants.EthBaseCurrency)
        });
        // When: getValue called

        // Then: getValue should be reverted
        vm.expectRevert(stdError.arithmeticError);
        floorERC1155PricingModule.getValue(getValueInput);
    }
}
