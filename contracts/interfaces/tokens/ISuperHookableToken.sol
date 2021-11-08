pragma solidity 0.7.6;
import {ISuperToken, IERC20} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {ISuperHookManager} from "./ISuperHookManager.sol";

interface ISuperHookableToken is ISuperToken {
    function initialize(
        IERC20 underlyingToken,
        uint8 underlyingDecimals,
        string calldata n,
        string calldata s,
        ISuperHookManager hookManager
    ) external;
}
