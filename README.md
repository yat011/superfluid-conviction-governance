# Superfluid Conviction Voting (Support Constant Flow Streaming)

This hackathon work provides a generic conviction voting tool, powered by superfluid framework, to enable the easy adoption of conviction voting. 

Our conviction voting implementation can automatically react to any constant Superfluid streaming changes. In other words, user can continuously increase/decrease their conviction voting power towards their favourite proposals while they are sending/receiving the governance tokens without extra transaction, lockup and staking.

# Run and Test Locally
```
yarn
npx hardhat test
```
# Example
see test/ConvictionAgreementV1.test.ts

# Methodology
Please find the detail here

https://medium.com/@yat192002/superfluid-conviction-voting-tool-hackathon-a37df3c6f8ab

# Parameter Explanation

When creating proposal, we need to pass a argument called "ProposalParam", i.e.
```
struct ProposalParam {
    uint256 alpha;
    uint256 requiredConviction;
    uint256 numSecondPerStep;
    uint256 tokenScalingFactor;
}
```
These controls how and when proposal gets passed.

- alpha: control the decay rate of conviction. value range [0-1]  * DECIMAL_MULTIPLIER (10^7). It is multiplied by DECIMAL_MULTIPLIER because solidity does not support float.
- requiredConviction: The threshold of passed proposal.  actual conviction * DECIMAL_MULTIPLIER (10^7)
- numSecondPerStep: This defines how many second represent one step in conviction calculation. 
  - ** Current version does not support fractional step, so step = floor(time duration/numSecondPerStep). Will improve it in this future.
- tokenScalingFactor:  determine how many token contribute to 1 voting power. e.g. 10^18 => 1 voting power

# Major Use Cases
- Create Proposal: The application-authorised person can create project in a pool determined by (SuperApp's address, ISuperHookableToken's address). All projects in the same pool share the voting powers from users.

- Vote Proposal: User can vote a project with a certain percentage of his/her voting power. E.g. he/she votes a project with 50% of his/her voting power. The actual amount of voting power towards the project will be automatically reflected when there is any change of his/her token amount.

- Manually Refresh Proposal's Status: Manually trigger on-chain calculation and set the Proposal Status.

# Components
- ConvictionAgreement: It implements the core logic which handles the conviction calculation, proposal creation, user voting, and the changes of proposal's status. Execution of a proposal is not included here, and we leave it to the application.


- SuperHookableToken and HookManager: To observe any transfer/mint/burn/agreement update of the token in order to update the conviction state accordingly.

- ConvictionApp: An example application which uses ConvictionAgreement. As the main voting logic is implemented in the agreement, the DAO application can focus on the execution, the content of proposal (e.g. string/code), etc.




# Future works
- Support fractional step in conviction calculation
- More test cases
- Optimize gas fee

