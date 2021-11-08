pragma solidity 0.7.6;
import {OverridableSuperToken} from "./OverridableSuperToken.sol";
import {OverridableSuperfluidToken} from "./OverridableSuperfluidToken.sol";
import {ISuperfluid} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {ISuperfluid, ISuperfluidGovernance, ISuperToken, ISuperfluidToken, ISuperAgreement, IERC20, IERC777, TokenInfo} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {ERC777Helper} from "@superfluid-finance/ethereum-contracts/contracts/utils/ERC777Helper.sol";
import {ISuperHookManager} from "../interfaces/tokens/ISuperHookManager.sol";
import {ISuperHookableToken} from "../interfaces/tokens/ISuperHookableToken.sol";

import {FixedSizeData} from "@superfluid-finance/ethereum-contracts/contracts/utils/FixedSizeData.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";

contract SuperHookableToken is ISuperHookableToken, OverridableSuperToken {
    using SignedSafeMath for int256;
    ISuperHookManager public _hookManager;

    constructor(ISuperfluid host) OverridableSuperToken(host) {}

    function initialize(
        IERC20 underlyingToken,
        uint8 underlyingDecimals,
        string calldata n,
        string calldata s,
        ISuperHookManager hookManager
    ) public override initializer {
        super.initialize(underlyingToken, underlyingDecimals, n, s);
        _hookManager = ISuperHookManager(hookManager);
    }

    function _mint(
        address operator,
        address account,
        uint256 amount,
        bool requireReceptionAck,
        bytes memory userData,
        bytes memory operatorData
    ) internal override {
        super._mint(
            operator,
            account,
            amount,
            requireReceptionAck,
            userData,
            operatorData
        );
        if (isContract(_hookManager)) {
            _hookManager.onMint(address(this), account, amount);
        }
    }

    function _burn(
        address operator,
        address from,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) internal override {
        super._burn(operator, from, amount, userData, operatorData);
        if (isContract(_hookManager)) {
            _hookManager.onBurn(address(this), from, amount);
        }
    }

    function _move(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) internal override {
        super._move(operator, from, to, amount, userData, operatorData);

        if (isContract(_hookManager)) {
            _hookManager.onTransfer(address(this), from, to, amount);
        }
    }

    /// @dev ISuperfluidToken.settleBalance implementation
    function settleBalance(address account, int256 delta)
        external
        override(OverridableSuperfluidToken, ISuperfluidToken)
        onlyAgreement
    {
        _balances[account] = _balances[account].add(delta);

        if (isContract(_hookManager)) {
            _hookManager.onSettleBalance(
                address(this),
                account,
                _balances[account],
                delta
            );
        }
    }

    /**************************************************************************
     * Super Agreement hosting functions
     *************************************************************************/
    /// @dev ISuperfluidToken.createAgreement implementation
    function createAgreement(bytes32 id, bytes32[] calldata data)
        external
        virtual
        override(OverridableSuperfluidToken, ISuperfluidToken)
    {
        address agreementClass = msg.sender;
        bytes32 slot = keccak256(
            abi.encode("AgreementData", agreementClass, id)
        );
        require(
            !FixedSizeData.hasData(slot, data.length),
            "SuperfluidToken: agreement already created"
        );
        FixedSizeData.storeData(slot, data);

        if (isContract(_hookManager)) {
            _hookManager.onCreateAgreement(
                address(this),
                agreementClass,
                id,
                data
            );
        }
        emit AgreementCreated(agreementClass, id, data);
    }

    /// @dev ISuperfluidToken.updateAgreementData implementation
    function updateAgreementData(bytes32 id, bytes32[] calldata data)
        external
        override(OverridableSuperfluidToken, ISuperfluidToken)
    {
        address agreementClass = msg.sender;
        bytes32 slot = keccak256(
            abi.encode("AgreementData", agreementClass, id)
        );
        FixedSizeData.storeData(slot, data);

        if (isContract(_hookManager)) {
            _hookManager.onUpdateAgreement(
                address(this),
                agreementClass,
                id,
                data
            );
        }
        emit AgreementUpdated(msg.sender, id, data);
    }

    /// @dev ISuperfluidToken.updateAgreementState implementation
    function updateAgreementStateSlot(
        address account,
        uint256 slotId,
        bytes32[] calldata slotData
    ) external override(OverridableSuperfluidToken, ISuperfluidToken) {
        bytes32 slot = keccak256(
            abi.encode("AgreementState", msg.sender, account, slotId)
        );
        FixedSizeData.storeData(slot, slotData);

        if (isContract(_hookManager)) {
            _hookManager.onUpdateAgreementState(
                address(this),
                msg.sender,
                account,
                slotId,
                slotData
            );
        }
        // FIXME change how this is done
        //_addAgreementClass(msg.sender, account);
        emit AgreementStateUpdated(msg.sender, account, slotId);
    }

    /// @dev ISuperfluidToken.terminateAgreement implementation
    function terminateAgreement(bytes32 id, uint256 dataLength)
        external
        override(OverridableSuperfluidToken, ISuperfluidToken)
    {
        address agreementClass = msg.sender;
        bytes32 slot = keccak256(
            abi.encode("AgreementData", agreementClass, id)
        );
        require(
            FixedSizeData.hasData(slot, dataLength),
            "SuperfluidToken: agreement does not exist"
        );
        FixedSizeData.eraseData(slot, dataLength);
        emit AgreementTerminated(msg.sender, id);
    }

    function isContract(ISuperHookManager manager)
        internal
        view
        returns (bool)
    {
        address addr = address(manager);
        uint256 size;
        if (addr == address(0x0)) return false;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}
