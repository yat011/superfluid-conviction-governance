// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {ISuperfluid, ISuperToken, SuperAppBase, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {IInstantDistributionAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IInstantDistributionAgreementV1.sol";
import {AgreementLibrary} from "@superfluid-finance/ethereum-contracts/contracts/agreements/AgreementLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IConvictionAgreementV1} from "./interfaces/agreements/IConvictionAgreementV1.sol";
import {ISuperAgreement} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperAgreement.sol";
import "hardhat/console.sol";

contract ConvictionApp is Ownable, SuperAppBase {
    IConvictionAgreementV1 private _ida;
    ISuperfluid private _host;

    constructor(ISuperfluid host, IConvictionAgreementV1 ida) {
        _host = host;
        _ida = ida;

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP;

        _host.registerApp(configWord);

        transferOwnership(msg.sender);
    }

    function afterAgreementCreated(
        ISuperToken superToken,
        address, /* agreementClass */
        bytes32 agreementId,
        bytes calldata, /*agreementData*/
        bytes calldata, /*cbdata*/
        bytes calldata ctx
    ) external override returns (bytes memory newCtx) {
        newCtx = ctx;
    }

    function beforeAgreementCreated(
        ISuperToken superToken,
        address agreementClass,
        bytes32, /* agreementId */
        bytes calldata, /*agreementData*/
        bytes calldata /*ctx*/
    ) external view override returns (bytes memory data) {
        ///Do auth here
        return new bytes(0);
    }

    function beforeAgreementUpdated(
        ISuperToken superToken,
        address agreementClass,
        bytes32, /* agreementId */
        bytes calldata, /*agreementData*/
        bytes calldata ctx
    ) external view override returns (bytes memory data) {
        // require(superToken == _cashToken, "DRT: Unsupported cash token");
        // require(agreementClass == address(_ida), "DRT: Unsupported agreement");
        address user = _getMsgSender(superToken, ctx);

        console.log("Before Updated user is:", user);
        return new bytes(0);
    }

    function afterAgreementUpdated(
        ISuperToken superToken,
        address, /* agreementClass */
        bytes32,
        bytes calldata data, /*agreementData*/
        bytes calldata, /*cbdata*/
        bytes calldata ctx
    ) external override returns (bytes memory newCtx) {
        console.log("superapp: afterAgreementUpdated");
        // _checkSubscription(superToken, ctx, agreementId);
        // address user = _getMsgSender(superToken, ctx);
        // console.log(string(data));
        // address user = _getMsgSender(superToken, ctx);
        // _print(superToken, user);

        newCtx = ctx;
    }

    function _getMsgSender(ISuperToken token, bytes calldata ctx)
        internal
        view
        returns (address)
    {
        ISuperfluid.Context memory currentContext = AgreementLibrary
            .authorizeTokenAccess(token, ctx);

        return currentContext.msgSender;
    }
}
