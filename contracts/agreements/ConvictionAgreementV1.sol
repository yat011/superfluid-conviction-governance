// SPDX-License-Identifier: AGPLv3
pragma solidity 0.7.6;
pragma abicoder v2;

import {ISuperfluid, ISuperfluidToken, ISuperfluidGovernance, ISuperApp, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {AgreementBase} from "@superfluid-finance/ethereum-contracts/contracts/agreements/AgreementBase.sol";
import {ConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/agreements/ConstantFlowAgreementV1.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {AgreementLibrary} from "@superfluid-finance/ethereum-contracts/contracts/agreements/AgreementLibrary.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {ITokenObserver, ISuperHookManager} from "../interfaces/tokens/ISuperHookManager.sol";
import {ISuperHookableToken} from "../interfaces/tokens/ISuperHookableToken.sol";
import {IConvictionAgreementV1} from "../interfaces/agreements/IConvictionAgreementV1.sol";
import {mathUtils} from "../utils/mathUtils.sol";

contract ConvictionAgreementV1 is IConvictionAgreementV1 {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    bytes32 public constant CONSTANT_FLOW_V1 =
        keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");

    ISuperHookManager _hookManager;

    constructor() {}

    struct UserTokenVoteData {
        address user;
        uint256 totalVotedPercentage;
        uint256[] votingProposals;
        mapping(uint256 => uint256) votingPercentage;
        mapping(uint256 => uint256) votingAmount;
        mapping(uint256 => int256) votingFlowRate;
    }

    struct ProposalIndex {
        ProposalData[] proposals;
        mapping(address => UserTokenVoteData) userData;
    }

    event ProposalCreated(
        address token,
        address app,
        uint256 proposalId,
        ProposalParam param
    );
    event UserVoted(
        address token,
        address app,
        uint256 proposalId,
        uint256 percentage
    );

    mapping(address => mapping(ISuperHookableToken => ProposalIndex)) _appTokenProposalIndex;
    mapping(address => mapping(ISuperHookableToken => AppProposalId[])) _userTokenProposalIndex;

    ///============ Conviction Agreement Interface functions ================

    function setHookManager(ISuperHookManager hookManager) external override {
        require(
            address(_hookManager) == address(0),
            "HookManager can be set once only"
        );
        _hookManager = hookManager;
    }

    function createProposal(
        ISuperHookableToken token,
        address app,
        ProposalParam calldata param,
        bytes calldata proposalData,
        bytes calldata ctx
    ) external override returns (bytes memory newCtx) {
        ISuperfluid.Context memory currentContext = AgreementLibrary
            .authorizeTokenAccess(token, ctx);

        ProposalIndex storage index = _appTokenProposalIndex[app][token];

        uint256 newProposalId = index.proposals.length;
        ProposalData memory proposal;
        proposal.proposalId = newProposalId;
        proposal.param = param;
        proposal.governToken = token;
        proposal.app = app;
        proposal.lastTimeStamp = block.timestamp;
        proposal.data = proposalData;
        index.proposals.push(proposal);

        bytes32 dataId = _generateDataId(app, newProposalId);

        _callBeforeAgreementCreated(token, app, newProposalId, ctx);

        token.createAgreement(dataId, encodeAgreementData(newProposalId));

        _callAfterAgreementCreated(token, app, newProposalId, ctx);
        newCtx = ctx;
    }

    function vote(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        uint256 percentage,
        bytes calldata ctx
    )
        external
        override
        onlyActiveProposal(app, token, proposalId)
        returns (bytes memory newCtx)
    {
        require(
            percentage >= 0 && percentage <= DECIMAL_MULTIPLIER,
            "Target Percentage must >=0 and <= 100%"
        );

        _callBeforeAgreementUpdated(
            token,
            app,
            proposalId,
            AGREEMENT_UPDATE_VOTING,
            ctx
        );

        UserTokenVoteData storage userTokenData;
        ProposalData storage proposal;
        ProposalIndex storage pIndex;
        {
            pIndex = _appTokenProposalIndex[app][token];
        }
        {
            address user = _getMsgSender(token, ctx);
            userTokenData = pIndex.userData[user];
            if (userTokenData.user == address(0)) {
                userTokenData.user = user;
            }
        }
        {
            proposal = pIndex.proposals[proposalId];
        }

        {
            _updateRelatedConvictionStates(token, app, userTokenData, ctx);
        }
        {
            _syncUserState(userTokenData, pIndex);
        }

        {
            _votePercentage(
                userTokenData.user,
                proposal,
                percentage,
                userTokenData
            );
        }
        emit UserVoted(address(token), app, proposalId, percentage);
        newCtx = ctx;

        _callAfterAgreementUpdated(
            token,
            app,
            proposalId,
            AGREEMENT_UPDATE_VOTING,
            ctx
        );
    }

    function updateProposalConvictionAndStatus(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        bytes calldata ctx
    )
        external
        override
        onlyActiveProposal(app, token, proposalId)
        returns (bytes memory newCtx)
    {
        ProposalIndex storage pIndex = _appTokenProposalIndex[app][token];
        {
            ProposalData storage proposal = pIndex.proposals[proposalId];

            _updateProposalConvictionAndStatus(proposal, ctx);
        }

        newCtx = ctx;
    }

    function getUserVotePercentage(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        address user
    ) public view override returns (uint256) {
        return
            _appTokenProposalIndex[app][token].userData[user].votingPercentage[
                proposalId
            ];
    }

    function getUserVoteAmount(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        address user
    ) public view override returns (uint256) {
        return
            _appTokenProposalIndex[app][token].userData[user].votingAmount[
                proposalId
            ];
    }

    function getUserVoteFlow(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        address user
    ) public view override returns (int256) {
        return
            _appTokenProposalIndex[app][token].userData[user].votingFlowRate[
                proposalId
            ];
    }

    function getVotingProposalsByAppUser(
        ISuperHookableToken token,
        address app,
        address user
    ) public view override returns (uint256[] memory) {
        uint256[] storage source = _appTokenProposalIndex[app][token]
            .userData[user]
            .votingProposals;
        uint256[] memory result = new uint256[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            result[i] = source[i];
        }
        return result;
    }

    function getVotingProposalsByUser(ISuperHookableToken token, address user)
        public
        view
        override
        returns (AppProposalId[] memory)
    {
        AppProposalId[] storage source = _userTokenProposalIndex[user][token];
        AppProposalId[] memory result = new AppProposalId[](source.length);
        for (uint256 i = 0; i < source.length; i++) {
            result[i] = source[i];
        }
        return result;
    }

    function getProposalLastConviction(
        ISuperHookableToken token,
        address app,
        uint256 proposalId
    ) public view override returns (uint256) {
        return
            _appTokenProposalIndex[app][token]
                .proposals[proposalId]
                .lastConviction;
    }

    function getProposal(
        ISuperHookableToken token,
        address app,
        uint256 proposalId
    ) public view override returns (ProposalData memory) {
        return _appTokenProposalIndex[app][token].proposals[proposalId];
    }

    /// @dev ISuperAgreement.realtimeBalanceOf implementation
    function realtimeBalanceOf(
        ISuperfluidToken token,
        address account,
        uint256 /* time */
    )
        external
        view
        override
        returns (
            int256 dynamicBalance,
            uint256 deposit,
            uint256 owedDeposit
        )
    {
        return (0, 0, 0);
    }

    function calculateConviction(
        uint256 numStep,
        uint256 initConviction,
        uint256 amount,
        int256 flowRate,
        uint256 alpha
    ) public view override returns (uint256) {
        // Y = a^x y_0 + (1-a^x)/(1-a) x_0 + \beta *(x * (1-a^x)/(1-a) - (a - a^x)/(1-a)^2 + (x-1)/(1-a)*a^x), x = time
        // A = a^t * y_0
        // Conviction_D = A  + B x + C * flowrate

        require(numStep >= 1, "Numstep needs to >= 1");

        uint256 alphaF128 = mathUtils.convertToFixedPoint128(
            alpha,
            DECIMAL_MULTIPLIER
        );
        uint256 alphaPowerStepF128 = mathUtils.fixedFractionalPow(
            alphaF128,
            numStep
        );
        uint256 oneMinusAlphaF128 = 0;
        uint256 oneMinusAlphaPowerStepF128 = 0;

        {
            uint256 oneF128 = mathUtils.convertToFixedPoint128(1, 1);
            oneMinusAlphaF128 = oneF128.sub(alphaF128);
            oneMinusAlphaPowerStepF128 = oneF128.sub(alphaPowerStepF128);
        }
        uint256 result = mathUtils
            .convertFixedPoint128To(alphaPowerStepF128, DECIMAL_MULTIPLIER)
            .mul(initConviction)
            .div(DECIMAL_MULTIPLIER);
        uint256 C_D;
        {
            uint256 BCoff_D = oneMinusAlphaPowerStepF128
                .mul(DECIMAL_MULTIPLIER)
                .div(oneMinusAlphaF128);

            C_D = BCoff_D.mul(numStep);
            result = result.add(amount.mul(BCoff_D).div(DECIMAL_MULTIPLIER));
        }

        C_D = C_D.add(
            alphaPowerStepF128
                .mul(DECIMAL_MULTIPLIER)
                .div(oneMinusAlphaF128)
                .mul(numStep - 1)
        );

        C_D = C_D.sub(
            alphaF128.sub(alphaPowerStepF128).mul(DECIMAL_MULTIPLIER).div(
                mathUtils.fixedFractionalPow(oneMinusAlphaF128, 2)
            )
        );

        if (flowRate > 0) {
            C_D = uint256(flowRate).mul(C_D).div(DECIMAL_MULTIPLIER);
            return result.add(C_D);
        } else if (flowRate < 0) {
            C_D = uint256(-flowRate).mul(C_D).div(DECIMAL_MULTIPLIER);
            if (C_D > result) {
                //Negative due to insolvent debt. Cap it to 0 now.
                return 0;
            }
            return result.sub(C_D);
        } else {
            return result;
        }
    }

    ///========================================

    function getNumStep(
        uint256 lastTimeStamp,
        uint256 currentTimeStamp,
        uint256 numPerUpdate
    ) public pure returns (uint256) {
        return (currentTimeStamp - lastTimeStamp).div(numPerUpdate);
    }

    function checkInsolvent(
        uint256 numStep,
        uint256 amount,
        int256 flowRate
    ) public view returns (bool) {
        if (flowRate < 0) {
            uint256 delta = uint256(-flowRate).mul(numStep);
            if (delta > amount) {
                //insolvent
                return true;
            }
        }

        return false;
    }

    ///@dev assume solvent
    function getMaxConvictionStep(
        uint256 initConviction,
        uint256 amount,
        int256 flowRate,
        uint256 alpha
    ) public view returns (int256) {
        // max/min = 1/ln(a) * ln(((a-1) * \beta)/((a^2 - 2 a + 1) ln(a) y_0 + (a-1) ln(a) x + a\beta ln(a)

        uint256 oneMinusA_D = DECIMAL_MULTIPLIER.sub(alpha);

        uint256 A_128 = mathUtils.convertToFixedPoint128(
            alpha,
            DECIMAL_MULTIPLIER
        );

        uint256 oneMinusAPower2_D = mathUtils.convertFixedPoint128To(
            mathUtils.fixedFractionalPow(
                mathUtils.convertToFixedPoint128(
                    oneMinusA_D,
                    DECIMAL_MULTIPLIER
                ),
                2
            ),
            DECIMAL_MULTIPLIER
        );

        int256 delt2ndDerivative_D;
        {
            int256 initConvEff_D = int256(
                oneMinusAPower2_D.mul(initConviction).div(DECIMAL_MULTIPLIER)
            );

            int256 amountEff_D = -int256(
                amount.mul(oneMinusA_D).div(DECIMAL_MULTIPLIER)
            );

            int256 flowEff_D = flowRate.mul(int256(alpha)).div(
                int256(DECIMAL_MULTIPLIER)
            );
            delt2ndDerivative_D = initConvEff_D + amountEff_D + flowEff_D;
        }
        // (alpha - 1) ** 2 *  y_0 + (a-1) x_0  + a (flowRate)
        if (delt2ndDerivative_D > 0) {
            return -1;
        }

        // max/min = 1/ln(a) * ln(((a-1) * \beta)/((a^2 - 2 a + 1) ln(a) y_0 + (a-1) ln(a) x + a\beta ln(a)

        {
            int256 ln_a_D = mathUtils.convertSignedFixedPoint128To(
                mathUtils.ln(A_128),
                DECIMAL_MULTIPLIER
            );
            int256 nom_D = (-int256(oneMinusA_D)).mul(flowRate).div(
                int256(DECIMAL_MULTIPLIER)
            ); //must be non negative, alpha<1, flowRate <=0

            int256 denom_D = ln_a_D.mul(delt2ndDerivative_D).div(
                int256(DECIMAL_MULTIPLIER)
            );

            int256 content = nom_D.mul(int256(DECIMAL_MULTIPLIER)).div(denom_D);
            if (content <= 0) {
                return -1;
            }

            int256 maxStep_D = mathUtils
                .convertSignedFixedPoint128To(
                    mathUtils.ln(
                        mathUtils.convertToFixedPoint128(
                            uint256(content),
                            DECIMAL_MULTIPLIER
                        )
                    ),
                    DECIMAL_MULTIPLIER
                )
                .mul(int256(DECIMAL_MULTIPLIER))
                .div(ln_a_D);

            if (maxStep_D < 0) {
                return -1;
            }

            return maxStep_D;
        }
    }

    /// @dev Only update conviction but not the state because do not have the context to trigger SuperApp Callback.
    function _updateUserProposalsOnCallBack(
        ISuperHookableToken token,
        address user
    ) internal {
        AppProposalId[] storage appProposalIds = _userTokenProposalIndex[user][
            token
        ];

        _updateConvictionOnlyWithAppProposalIds(token, appProposalIds);

        _updateVotingWithAppProposalIds(token, user, appProposalIds);
    }

    function _getMsgSender(ISuperHookableToken token, bytes calldata ctx)
        internal
        returns (address)
    {
        ISuperfluid.Context memory currentContext = AgreementLibrary
            .authorizeTokenAccess(token, ctx);

        return currentContext.msgSender;
    }

    function _updateRelatedConvictionStates(
        ISuperHookableToken token,
        address app,
        UserTokenVoteData storage userTokenData,
        bytes calldata ctx
    ) internal {
        for (
            int256 i = int256(userTokenData.votingProposals.length) - 1;
            i >= 0;
            i--
        ) {
            uint256 proposalId = userTokenData.votingProposals[uint256(i)];

            ProposalData storage p = _appTokenProposalIndex[app][token]
                .proposals[proposalId];

            _updateProposalConvictionAndStatus(p, ctx);
        }
    }

    function _updateConvictionOnlyWithAppProposalIds(
        ISuperHookableToken token,
        AppProposalId[] storage appProposalIds
    ) internal {
        for (int256 i = int256(appProposalIds.length) - 1; i >= 0; i--) {
            AppProposalId storage apId = appProposalIds[uint256(i)];
            ProposalData storage p = _appTokenProposalIndex[apId.app][token]
                .proposals[apId.proposalId];
            if (p.status != ProposalStatus.Active) {
                continue;
            }

            _updateConvictionAndCheckStatus(p);
        }
    }

    function _updateVotingWithAppProposalIds(
        ISuperHookableToken token,
        address user,
        AppProposalId[] storage appProposalIds
    ) internal {
        for (int256 i = int256(appProposalIds.length) - 1; i >= 0; i--) {
            AppProposalId storage apId = appProposalIds[uint256(i)];
            ProposalData storage p = _appTokenProposalIndex[apId.app][token]
                .proposals[apId.proposalId];

            UserTokenVoteData storage userTokenData = _appTokenProposalIndex[
                apId.app
            ][token].userData[user];

            _votePercentage(
                user,
                p,
                userTokenData.votingPercentage[p.proposalId], //remains unchanged
                userTokenData
            );
        }
    }

    function _syncUserState(
        UserTokenVoteData storage userTokenData,
        ProposalIndex storage index
    ) internal {
        // _update
        uint256 newTotalVotedPercentage = userTokenData.totalVotedPercentage;

        for (
            int256 i = int256(userTokenData.votingProposals.length) - 1;
            i >= 0;
            i--
        ) {
            uint256 proposalId = userTokenData.votingProposals[uint256(i)];

            ProposalData storage p = index.proposals[proposalId];

            if (_isProposalEnded(p)) {
                uint256 freedPercentage = userTokenData.votingPercentage[
                    proposalId
                ];
                newTotalVotedPercentage = newTotalVotedPercentage.sub(
                    freedPercentage
                );
                _deleteProposalId(userTokenData.votingProposals, proposalId);

                _deleteAppProposalId(
                    _userTokenProposalIndex[userTokenData.user][p.governToken],
                    p.app,
                    p.proposalId
                );

                userTokenData.votingPercentage[proposalId] = 0;
            }
        }
        userTokenData.totalVotedPercentage = newTotalVotedPercentage;
    }

    function _votePercentage(
        address user,
        ProposalData storage targetProposal,
        uint256 targetPercentage,
        UserTokenVoteData storage userTokenData
    ) internal {
        require(targetPercentage >= 0, "Voting Percentage >= 0");

        if (targetProposal.status != ProposalStatus.Active) {
            return;
        }

        uint256 votingAmount;
        {
            int256 balance = getAllBalance(targetProposal.governToken, user);
            if (balance < 0) {
                //insolvent;
                balance = 0;
                targetPercentage = 0;
            }

            votingAmount = uint256(balance)
                .mul(DECIMAL_MULTIPLIER)
                .div(targetProposal.param.tokenScalingFactor)
                .mul(targetPercentage)
                .div(DECIMAL_MULTIPLIER);

            targetProposal.amount = targetProposal
                .amount
                .sub(userTokenData.votingAmount[targetProposal.proposalId])
                .add(votingAmount);
        }

        {
            userTokenData.totalVotedPercentage = userTokenData
                .totalVotedPercentage
                .sub(userTokenData.votingPercentage[targetProposal.proposalId])
                .add(targetPercentage);
            require(
                userTokenData.totalVotedPercentage <= DECIMAL_MULTIPLIER,
                "Total Voting Percentage must <= 100%"
            );
        }

        userTokenData.votingPercentage[
            targetProposal.proposalId
        ] = targetPercentage;
        userTokenData.votingAmount[targetProposal.proposalId] = votingAmount;

        {
            ISuperfluid sf = ISuperfluid(targetProposal.governToken.getHost());
            IConstantFlowAgreementV1 flowAgreement = IConstantFlowAgreementV1(
                address(sf.getAgreementClass(CONSTANT_FLOW_V1))
            );
            (, int96 flowRate, , ) = flowAgreement.getAccountFlowInfo(
                targetProposal.governToken,
                user
            );

            int256 userFlowRate = int256(flowRate)
                .mul(int256(DECIMAL_MULTIPLIER))
                .div(int256(targetProposal.param.tokenScalingFactor))
                .mul(int256(targetProposal.param.numSecondPerStep))
                .mul(int256(targetPercentage))
                .div(int256(DECIMAL_MULTIPLIER));

            targetProposal.flowRate = targetProposal
                .flowRate
                .sub(userTokenData.votingFlowRate[targetProposal.proposalId])
                .add(userFlowRate);

            userTokenData.votingFlowRate[
                targetProposal.proposalId
            ] = userFlowRate;
        }
        {
            if (targetPercentage == 0) {
                _deleteProposalId(
                    userTokenData.votingProposals,
                    targetProposal.proposalId
                );
                _deleteAppProposalId(
                    _userTokenProposalIndex[user][targetProposal.governToken],
                    targetProposal.app,
                    targetProposal.proposalId
                );
            } else {
                _upsertProposalId(
                    userTokenData.votingProposals,
                    targetProposal.proposalId
                );

                _upsertAppProposalIndex(
                    _userTokenProposalIndex[user][targetProposal.governToken],
                    AppProposalId({
                        app: targetProposal.app,
                        proposalId: targetProposal.proposalId
                    })
                );
            }
        }
    }

    function _isProposalEnded(ProposalData storage p) internal returns (bool) {
        return
            p.status == ProposalStatus.Pass ||
            p.status == ProposalStatus.Insolvent;
    }

    function _updateProposalConvictionAndStatus(
        ProposalData storage p,
        bytes calldata ctx
    ) internal {
        (
            bool changed,
            ProposalStatus newStatus
        ) = _updateConvictionAndCheckStatus(p);

        if (changed) {
            _callBeforeAgreementUpdated(
                p.governToken,
                p.app,
                p.proposalId,
                AGREEMENT_UPDATE_STATUS,
                ctx
            );
            p.status = newStatus;
            _callAfterAgreementUpdated(
                p.governToken,
                p.app,
                p.proposalId,
                AGREEMENT_UPDATE_STATUS,
                ctx
            );
        }
    }

    function _updateConvictionAndCheckStatus(ProposalData storage p)
        internal
        returns (bool statusChanged, ProposalStatus newStatus)
    {
        uint256 numStep = getNumStep(
            p.lastTimeStamp,
            uint256(block.timestamp),
            p.param.numSecondPerStep
        );

        (statusChanged, newStatus) = _getNewProposalStatus(p); // conviction could be precomputed due to hook;
        if (statusChanged) {
            return (statusChanged, newStatus);
        }

        _updateProposalConviction(p, numStep);

        (statusChanged, newStatus) = _getNewProposalStatus(p);
        if (statusChanged) {
            return (statusChanged, newStatus);
        }

        return (false, p.status);
    }

    function _updateProposalConviction(ProposalData storage p, uint256 numStep)
        internal
    {
        CalculationInput memory input = CalculationInput({
            lastTimeStamp: p.lastTimeStamp,
            lastConviction: p.lastConviction,
            amount: p.amount,
            flowRate: p.flowRate,
            alpha: p.param.alpha,
            numSecondPerStep: p.param.numSecondPerStep,
            status: p.status,
            requiredConviction: p.param.requiredConviction
        });

        (
            uint256 latestConviction,
            uint256 latestActiveTimeStamp
        ) = getLatestActiveConviction(input, numStep);

        p.lastConviction = latestConviction;
        p.lastTimeStamp = latestActiveTimeStamp;
    }

    function getLatestActiveConviction(
        CalculationInput memory input,
        uint256 numStep
    )
        public
        view
        override
        returns (uint256 latestConviction, uint256 latestTimeStamp)
    {
        if (input.status != ProposalStatus.Active) {
            return (input.lastConviction, input.lastTimeStamp);
        }

        if (numStep == 0) {
            return (input.lastConviction, input.lastTimeStamp);
        }

        if (input.flowRate < 0) {
            int256 maxStep_D = getMaxConvictionStep(
                input.lastConviction,
                input.amount,
                input.flowRate,
                input.alpha
            );
            if (maxStep_D >= 0) {
                uint256 maxStep = uint256(maxStep_D).div(DECIMAL_MULTIPLIER); //integer division;
                if (numStep >= maxStep) {
                    uint256 maxConviction = calculateConviction(
                        maxStep,
                        input.lastConviction,
                        input.amount,
                        input.flowRate,
                        input.alpha
                    );

                    if (maxConviction >= input.requiredConviction) {
                        return (
                            maxConviction,
                            input.lastTimeStamp.add(
                                maxStep.mul(input.numSecondPerStep)
                            )
                        );
                    }
                }
            }

            if (checkInsolvent(numStep, input.amount, input.flowRate)) {
                return (0, 0);
            }
        }
        uint256 currentConviction = calculateConviction(
            numStep,
            input.lastConviction,
            input.amount,
            input.flowRate,
            input.alpha
        );
        return (
            currentConviction,
            input.lastTimeStamp.add(numStep.mul(input.numSecondPerStep))
        );
    }

    function _getNewProposalStatus(ProposalData storage p)
        internal
        returns (bool changed, ProposalStatus nextStatus)
    {
        if (p.status != ProposalStatus.Active) {
            return (false, p.status);
        }

        if (p.lastConviction >= p.param.requiredConviction) {
            return (true, ProposalStatus.Pass);
        }

        if (p.lastTimeStamp == 0) {
            return (true, ProposalStatus.Insolvent);
        }
    }

    function _generateDataId(address app, uint256 proposalId)
        private
        pure
        returns (bytes32 id)
    {
        return keccak256(abi.encode(app, proposalId));
    }

    function encodeAgreementData(uint256 proposalId)
        public
        pure
        returns (bytes32[] memory)
    {
        bytes32[] memory data = new bytes32[](1);

        data[0] = bytes32(proposalId);

        return data;
    }

    //============ Array =============

    function _findProposalId(uint256[] storage proposalIds, uint256 pId)
        internal
        returns (int256)
    {
        int256 targetIndex = -1;
        for (uint256 i = 0; i < proposalIds.length; i++) {
            if (proposalIds[i] == pId) {
                targetIndex = int256(i);
                break;
            }
        }
        return targetIndex;
    }

    function _findAppProposalId(
        AppProposalId[] storage proposals,
        address app,
        uint256 proposalId
    ) internal returns (int256) {
        int256 targetIndex = -1;
        for (uint256 i = 0; i < proposals.length; i++) {
            if (
                proposals[i].app == app && proposals[i].proposalId == proposalId
            ) {
                targetIndex = int256(i);
                break;
            }
        }
        return targetIndex;
    }

    function _upsertProposalId(uint256[] storage array, uint256 item) internal {
        int256 index = _findProposalId(array, item);

        if (index == -1) {
            array.push(item);
        }
    }

    function _upsertAppProposalIndex(
        AppProposalId[] storage array,
        AppProposalId memory item
    ) internal {
        int256 index = _findAppProposalId(array, item.app, item.proposalId);

        if (index == -1) {
            array.push(item);
        }
    }

    function _deleteProposalId(uint256[] storage self, uint256 item)
        internal
        returns (bool)
    {
        uint256 length = self.length;
        for (uint256 i = 0; i < length; i++) {
            if (self[i] == item) {
                uint256 newLength = self.length - 1;
                if (i != newLength) {
                    self[i] = self[newLength];
                }
                delete self[newLength];
                self.pop();

                return true;
            }
        }
        return false;
    }

    function _deleteAppProposalId(
        AppProposalId[] storage self,
        address app,
        uint256 proposalId
    ) internal returns (bool) {
        uint256 length = self.length;
        for (uint256 i = 0; i < length; i++) {
            if (self[i].app == app && self[i].proposalId == proposalId) {
                uint256 newLength = self.length - 1;
                delete self[i];

                if (i != newLength) {
                    self[i] = self[newLength];
                }
                self.pop();

                return true;
            }
        }
        return false;
    }

    //===========  Agreement Call ============
    function _callBeforeAgreementCreated(
        ISuperHookableToken token,
        address account,
        uint256 proposalId,
        bytes calldata ctx
    ) internal {
        AgreementLibrary.CallbackInputs memory cbStates;
        cbStates = AgreementLibrary.createCallbackInputs(
            token,
            account,
            bytes32(proposalId),
            ""
        );

        cbStates.noopBit = SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP;
        AgreementLibrary.callAppBeforeCallback(cbStates, ctx);
    }

    function _callAfterAgreementCreated(
        ISuperHookableToken token,
        address account,
        uint256 proposalId,
        bytes calldata ctx
    ) internal {
        AgreementLibrary.CallbackInputs memory cbStates;
        cbStates = AgreementLibrary.createCallbackInputs(
            token,
            account,
            bytes32(proposalId),
            ""
        );

        cbStates.noopBit = SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP;
        AgreementLibrary.callAppAfterCallback(cbStates, new bytes(0), ctx);
    }

    function _callBeforeAgreementUpdated(
        ISuperHookableToken token,
        address account,
        uint256 proposalId,
        bytes memory updateType,
        bytes calldata ctx
    ) internal {
        AgreementLibrary.CallbackInputs memory cbStates;
        cbStates = AgreementLibrary.createCallbackInputs(
            token,
            account,
            bytes32(proposalId),
            bytes(updateType)
        );

        cbStates.noopBit = SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP;
        AgreementLibrary.callAppBeforeCallback(cbStates, ctx);
    }

    function _callAfterAgreementUpdated(
        ISuperHookableToken token,
        address account,
        uint256 proposalId,
        bytes memory updateType,
        bytes calldata ctx
    ) internal {
        AgreementLibrary.CallbackInputs memory cbStates;
        cbStates = AgreementLibrary.createCallbackInputs(
            token,
            account,
            bytes32(proposalId),
            bytes(updateType)
        );

        cbStates.noopBit = SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP;
        AgreementLibrary.callAppAfterCallback(cbStates, new bytes(0), ctx);
    }

    function _getConstantFlowAgreement(ISuperHookableToken token)
        internal
        returns (IConstantFlowAgreementV1)
    {
        ISuperfluid sf = ISuperfluid(token.getHost());
        IConstantFlowAgreementV1 flowAgreement = IConstantFlowAgreementV1(
            address(sf.getAgreementClass(CONSTANT_FLOW_V1))
        );

        return flowAgreement;
        // (, int96 flowRate, , ) = flowAgreement.getAccountFlowInfo(
        //     targetProposal.governToken,
        //     user
        // );
    }

    function getAllBalance(ISuperHookableToken token, address account)
        public
        override
        returns (int256)
    {
        (int256 availableBalance, uint256 deposit, uint256 owedDeposit) = token
            .realtimeBalanceOf(account, block.timestamp);

        int256 allBalance = availableBalance.add(
            (deposit > owedDeposit ? int256(deposit - owedDeposit) : 0)
        );

        return allBalance;
    }

    //========= Hook =======

    function onUpdateAgreementState(
        address token,
        address sender,
        address account,
        uint256 id,
        bytes32[] calldata data
    ) external override onlyHookManager {
        ISuperHookableToken hookableToken = ISuperHookableToken(token);
        IConstantFlowAgreementV1 agreement = _getConstantFlowAgreement(
            hookableToken
        );
        if (sender != address(agreement)) {
            return;
        }
        _refreshOnUserBalanceFlow(token, account);
    }

    function onSend(
        address token,
        address from,
        uint256 amount
    ) external override onlyHookManager {
        _refreshOnUserBalanceFlow(token, from);
    }

    function onReceive(
        address token,
        address to,
        uint256 amount
    ) external override onlyHookManager {
        _refreshOnUserBalanceFlow(token, to);
    }

    function onBurn(
        address token,
        address from,
        uint256 amount
    ) external override onlyHookManager {
        _refreshOnUserBalanceFlow(token, from);
    }

    function onMint(
        address token,
        address to,
        uint256 amount
    ) external override onlyHookManager {
        _refreshOnUserBalanceFlow(token, to);
    }

    function onSettle(
        address token,
        address account,
        int256 amount,
        int256 delta
    ) external override onlyHookManager {
        _refreshOnUserBalanceFlow(token, account);
    }

    function _refreshOnUserBalanceFlow(address token, address account)
        internal
    {
        ISuperHookableToken hookableToken = ISuperHookableToken(token);
        if (_userTokenProposalIndex[account][hookableToken].length > 0) {
            _updateUserProposalsOnCallBack(hookableToken, account);
        }
    }

    //========= Modifier ===========

    modifier onlyActiveProposal(
        address app,
        ISuperHookableToken token,
        uint256 proposalId
    ) {
        require(
            proposalId < _appTokenProposalIndex[app][token].proposals.length,
            "ProposalId does not exist."
        );
        ProposalData storage proposal = _appTokenProposalIndex[app][token]
            .proposals[proposalId];
        require(
            proposal.status == ProposalStatus.Active,
            "Can only vote Active Proposal"
        );

        require(
            proposal.governToken == token,
            "Token must match the governance token of the proposal"
        );
        _;
    }

    modifier onlyHookManager() {
        require(
            msg.sender == address(_hookManager),
            "Only hook manager can call"
        );
        _;
    }
}
