// SPDX-License-Identifier: AGPLv3
pragma solidity 0.7.6;
pragma abicoder v2;

import {AgreementBase} from "@superfluid-finance/ethereum-contracts/contracts/agreements/AgreementBase.sol";
import {ISuperHookableToken} from "../tokens/ISuperHookableToken.sol";
import {ITokenObserver, ISuperHookManager} from "../tokens/ISuperHookManager.sol";

abstract contract IConvictionAgreementV1 is AgreementBase, ITokenObserver {
    bytes public constant AGREEMENT_UPDATE_STATUS =
        abi.encodePacked("AGREEMENT_UPDATE_STATUS");
    bytes public constant AGREEMENT_UPDATE_VOTING =
        abi.encodePacked("AGREEMENT_UPDATE_VOTING");

    uint256 public constant DECIMAL_MULTIPLIER = 10000000; //demicals for conviction/param

    struct ProposalParam {
        uint256 alpha;
        uint256 requiredConviction;
        uint256 numSecondPerStep;
        uint256 tokenScalingFactor;
    }
    enum ProposalStatus {
        Active,
        Pass,
        Insolvent
    }

    struct ProposalData {
        uint256 proposalId;
        address app;
        ISuperHookableToken governToken;
        uint256 lastTimeStamp;
        uint256 lastConviction;
        uint256 amount; //scaled token amount
        int256 flowRate; //scaled, per step instead of second
        ProposalStatus status;
        ProposalParam param;
        bytes data; // app-dependent data
    }
    struct AppProposalId {
        address app;
        uint256 proposalId;
    }

    struct CalculationInput {
        uint256 lastTimeStamp;
        uint256 lastConviction;
        uint256 amount; //scaled token amount
        int256 flowRate; //scaled, per step instead of second
        uint256 alpha;
        uint256 numSecondPerStep;
        ProposalStatus status;
        uint256 requiredConviction;
    }

    /// @dev ISuperAgreement.agreementType implementation
    function agreementType() external view override returns (bytes32) {
        return keccak256("hackathon.ConvictionAgreement.v1");
    }

    function setHookManager(ISuperHookManager hookManager) external virtual;

    function createProposal(
        ISuperHookableToken token,
        address app,
        ProposalParam calldata param,
        bytes calldata proposalData,
        bytes calldata ctx
    ) external virtual returns (bytes memory newCtx);

    function vote(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        uint256 percentage,
        bytes calldata ctx
    ) external virtual returns (bytes memory newCtx);

    function updateProposalConvictionAndStatus(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        bytes calldata ctx
    ) external virtual returns (bytes memory newCtx);

    function getUserVotePercentage(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        address user
    ) public view virtual returns (uint256);

    function getUserVoteAmount(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        address user
    ) public view virtual returns (uint256);

    function getUserVoteFlow(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        address user
    ) public view virtual returns (int256);

    function getVotingProposalsByAppUser(
        ISuperHookableToken token,
        address app,
        address user
    ) public view virtual returns (uint256[] memory);

    function getVotingProposalsByUser(ISuperHookableToken token, address user)
        public
        view
        virtual
        returns (AppProposalId[] memory);

    function getProposalLastConviction(
        ISuperHookableToken token,
        address app,
        uint256 proposalId
    ) public view virtual returns (uint256);

    function getProposal(
        ISuperHookableToken token,
        address app,
        uint256 proposalId
    ) public view virtual returns (ProposalData memory);

    ///@dev return the latest conviction when the proposal is active;
    ///     Takes local maximum into account;
    ///     If insolvent, return (0,0)
    function getLatestActiveConviction(
        CalculationInput memory input,
        uint256 numStep
    )
        public
        view
        virtual
        returns (uint256 latestConviction, uint256 latestTimeStamp);

    function calculateConviction(
        uint256 numStep,
        uint256 initConviction,
        uint256 amount,
        int256 flowRate,
        uint256 alpha
    ) public view virtual returns (uint256);

    function getAllBalance(ISuperHookableToken token, address account)
        public
        virtual
        returns (int256);
}
