// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {ISuperfluid, ISuperToken, SuperAppBase, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {IInstantDistributionAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IInstantDistributionAgreementV1.sol";
import {AgreementLibrary} from "@superfluid-finance/ethereum-contracts/contracts/agreements/AgreementLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ISuperAgreement} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperAgreement.sol";
import {IConvictionAgreementV1} from "../interfaces/agreements/IConvictionAgreementV1.sol";
import "hardhat/console.sol";

contract TestApp is Ownable, SuperAppBase {
    IConvictionAgreementV1 private _agreement;
    ISuperfluid private _host;

    constructor(ISuperfluid host, IConvictionAgreementV1 agreement) {
        _host = host;
        _agreement = agreement;

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
        return new bytes(0);
    }

    function beforeAgreementUpdated(
        ISuperToken superToken,
        address agreementClass,
        bytes32, /* agreementId */
        bytes calldata, /*agreementData*/
        bytes calldata ctx
    ) external view override returns (bytes memory data) {
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
        newCtx = ctx;
    }
}
