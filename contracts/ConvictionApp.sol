// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {ISuperfluid, ISuperToken, SuperAppBase, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {IInstantDistributionAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IInstantDistributionAgreementV1.sol";
import {AgreementLibrary} from "@superfluid-finance/ethereum-contracts/contracts/agreements/AgreementLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IConvictionAgreementV1} from "./interfaces/agreements/IConvictionAgreementV1.sol";
import {ISuperHookableToken} from "./interfaces/tokens/ISuperHookableToken.sol";
import {ISuperAgreement} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperAgreement.sol";
import "hardhat/console.sol";

///@dev Example of ConvictionVotingApp
contract ConvictionApp is Ownable, SuperAppBase {
    IConvictionAgreementV1 private _agreement;
    ISuperfluid private _host;
    ISuperHookableToken _token;

    event ProposalPassed(address token, uint256 proposalId);
    event UserVoted(address token, uint256 proposalId);
    event ProposalExecuted(uint256 proposalId, bytes content);

    uint256[] _passedProposalIds;
    mapping(uint256 => bool) _executed;

    constructor(
        ISuperfluid host,
        IConvictionAgreementV1 agreement,
        ISuperHookableToken token
    ) {
        _host = host;
        _agreement = agreement;
        _token = token;

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP;

        _host.registerApp(configWord);

        transferOwnership(msg.sender);
    }

    function execute(uint256 proposalId) external {
        require(_executed[proposalId] == false, "Already Executed");
        IConvictionAgreementV1.ProposalData memory pData = _agreement
            .getProposal(
                ISuperHookableToken(address(_token)),
                address(this),
                proposalId
            );

        require(
            pData.status == IConvictionAgreementV1.ProposalStatus.Pass,
            "Can only execute Passed Proposal"
        );

        _executed[proposalId] = true;

        emit ProposalExecuted(proposalId, pData.data);
    }

    ///@dev In this example, our proposal data is just a string
    function encodeData(string calldata data)
        public
        pure
        returns (bytes memory)
    {
        return bytes(data);
    }

    ///@dev In this example, our proposal data is just a string
    function decodeData(bytes calldata data)
        public
        pure
        returns (string memory)
    {
        return string(data);
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
        bytes calldata ctx /*ctx*/
    ) external view override returns (bytes memory data) {
        ///Do auth here
        require(agreementClass == address(_agreement), "Unsupported agreement");
        require(address(_token) == address(superToken), "Unsupported token");

        // In this example, only owner of this app can create proposal
        address msgSender = _getMsgSender(superToken, ctx);

        require(msgSender == owner(), "Only owner can create proposal");

        return new bytes(0);
    }

    function beforeAgreementUpdated(
        ISuperToken superToken,
        address agreementClass,
        bytes32, /* agreementId */
        bytes calldata, /*agreementData*/
        bytes calldata ctx
    ) external view override returns (bytes memory data) {
        require(agreementClass == address(_agreement), "Unsupported agreement");
        require(address(_token) == address(superToken), "Unsupported token");
        address user = _getMsgSender(superToken, ctx);
        console.log("Before Updated user is:", user);
        return new bytes(0);
    }

    function afterAgreementUpdated(
        ISuperToken superToken,
        address, /* agreementClass */
        bytes32 aId,
        bytes calldata data, /*agreementData*/
        bytes calldata, /*cbdata*/
        bytes calldata ctx
    ) external override returns (bytes memory newCtx) {
        if (
            keccak256(data) == keccak256(_agreement.AGREEMENT_UPDATE_STATUS())
        ) {
            uint256 proposalId = uint256(aId);
            IConvictionAgreementV1.ProposalData memory pData = _agreement
                .getProposal(
                    ISuperHookableToken(address(superToken)),
                    address(this),
                    proposalId
                );

            if (pData.status == IConvictionAgreementV1.ProposalStatus.Pass) {
                _passedProposalIds.push(proposalId);
                emit ProposalPassed(address(superToken), proposalId);
            }
        } else if (
            keccak256(data) == keccak256(_agreement.AGREEMENT_UPDATE_VOTING())
        ) {
            uint256 proposalId = uint256(aId);
            emit UserVoted(address(superToken), proposalId);
        }

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
