import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
  name: "UMA Verification: Basic Platform Initialization",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const block = chain.mineBlock([
      Tx.contractCall('uma-verification', 'get-platform-statistics', [], deployer.address)
    ]);

    block.receipts[0].result.expectOk().expectTuple();
  }
}); 

Clarinet.test({
  name: "UMA Verification: Auditor Application Flow",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const alice = accounts.get('wallet_1')!;
    const deployer = accounts.get('deployer')!;

    const block1 = chain.mineBlock([
      Tx.contractCall('uma-verification', 'submit-auditor-application', 
        [
          types.ascii('Alice Auditor'),
          types.ascii('SecureAudit Inc.'),
          types.ascii('https://secureaudit.com'),
          types.ascii('Professional certification details')
        ], 
        alice.address)
    ]);

    block1.receipts[0].result.expectOk();

    const block2 = chain.mineBlock([
      Tx.contractCall('uma-verification', 'approve-auditor-application', 
        [types.principal(alice.address)], 
        deployer.address)
    ]);

    block2.receipts[0].result.expectOk();
  }
});

Clarinet.test({
  name: "UMA Verification: Contract Certification Request",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const bob = accounts.get('wallet_2')!;

    const block = chain.mineBlock([
      Tx.contractCall('uma-verification', 'request-contract-certification', 
        [
          types.principal(bob.address), 
          types.ascii('1.0.0'), 
          types.ascii('Sample contract description'), 
          types.ascii('https://github.com/sample-contract')
        ], 
        bob.address)
    ]);

    block.receipts[0].result.expectOk();
  }
});

Clarinet.test({
  name: "UMA Verification: Contract Verification Status",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const bob = accounts.get('wallet_2')!;

    const block = chain.mineBlock([
      Tx.contractCall('uma-verification', 'verify-contract-status', 
        [types.principal(bob.address), types.ascii('1.0.0')], 
        bob.address)
    ]);

    block.receipts[0].result.expectOk().expectBool(false);
  }
});