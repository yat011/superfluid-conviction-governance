# Superfluid Conviction Voting (Support Constant Flow Streaming)

This hackathon work provides a generic conviction voting tool, powered by superfluid framework, to enable the easy adoption of conviction voting. 

Our conviction voting implementation can automatically react to any constant Superfluid streaming changes. In other words, user can continuously increase/decrease their conviction voting power towards their favourite proposals while they are sending/receiving the governance tokens without extra transaction, lockup and staking.

# Run and Test Locally
```
yarn
npx hardhat test
```

# Methodology
Please find the detail here

https://medium.com/@yat192002/superfluid-conviction-voting-tool-hackathon-a37df3c6f8ab

# Major Use Cases
- Create Proposal: The application-authorised person can create project in a pool determined by (SuperApp's address, ISuperHookableToken's address). All projects in the same pool share the voting powers from users.

- Vote Proposal: User can vote a project with a certain percentage of his/her voting power. E.g. he/she votes a project with 50% of his/her voting power. The actual amount of voting power towards the project will be automatically reflected when there is any change of his/her token amount.

- Manually Refresh Proposal's Status: Manually trigger on-chain calculation and set the Proposal Status.

# Components
- ConvictionAgreement: It implements the core logic which handles the conviction calculation, proposal creation, user voting, and the changes of proposal's status. Execution of a proposal is not included here, and we leave it to the application.


- SuperHookableToken and HookManager: To observe any transfer/mint/burn/agreement update of the token in order to update the conviction state accordingly.

- ConvictionApp: An example application which uses ConvictionAgreement. As the main voting logic is implemented in the agreement, the DAO application can focus on the execution, the content of proposal (e.g. string/code), etc.


# Future works
- More test cases
- Optimize gas fee

