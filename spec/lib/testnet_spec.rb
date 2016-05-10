require 'spec_helper'

describe OnChain do
  
  it "should give me a balance for a testnet address" do
    
    bal1 = OnChain::BlockChain.get_balance('myDsUrM5Sd7SjpnWXnQARyTriVAPfLQbt8', :testnet3)
    OnChain::BlockChain.cache_write('myDsUrM5Sd7SjpnWXnQARyTriVAPfLQbt8', nil)
    
    expect(bal1).to eq(0.216)
    
    bal1 = OnChain::BlockChain.get_balance('myDsUrM5Sd7SjpnWXnQARyTriVAPfLQbt8')
    OnChain::BlockChain.cache_write('myDsUrM5Sd7SjpnWXnQARyTriVAPfLQbt8', nil)
    
    expect(bal1).to eq(0.0)
    
    bal1 = OnChain::BlockChain.get_balance('myDsUrM5Sd7SjpnWXnQARyTriVAPfLQbt8', :bitcoin)
    OnChain::BlockChain.cache_write('myDsUrM5Sd7SjpnWXnQARyTriVAPfLQbt8', nil)
    
    expect(bal1).to eq(0.0)
    
  end
  
  it "should give me the unspent outs" do
    
    out1 = OnChain::BlockChain.get_unspent_outs('myDsUrM5Sd7SjpnWXnQARyTriVAPfLQbt8', :testnet3)
    
    expect(out1.count).to eq(4)
  end
  
  it "should create a single address transaction" do
    
    
    tx, inputs_to_sign = OnChain::Transaction.create_single_address_transaction(
      'myDsUrM5Sd7SjpnWXnQARyTriVAPfLQbt8', 
      'mx97L7gTbERp8B7EK7Bk8R7bgnq6zUKAgY', 4000000, 
      0.01, 'mkk7dRJz4288ux6kLmFi1w6GcHjJowtFc8', 40000, :testnet3)
      
    expect(tx).to eq('010000000172c9c589bb26fe8dcf2f29c562cbc807c6819ae1015c1aa4898ca6209218d2c3010000001976a914c2372ca390730d5cb2983736c8aa0959bf9cb9ef88acffffffff0300093d00000000001976a914b6588798023037135a20583ce2c6610e36c6ead888ac30750000000000001976a9143955d3f58ee2d7b941ff7583de109da70d1b8a6288ac60541900000000001976a914c2372ca390730d5cb2983736c8aa0959bf9cb9ef88ac00000000')
    
  end
  
  it "should create a transaction" do
    
    redemption_scripts = ["5221032c6c755d5da9c9e442bc4fdd08680d27e52b55bdefe8f664e7df2726686a2bf72102787adcb5648253eaf437f7fa516c4defbfd2f6fea896cfe2ca644330212390d352ae", "5221032c6c755d5da9c9e442bc4fdd08680d27e52b55bdefe8f664e7df2726686a2bf72102835743a35a8bd08cc5c2c9a0a814ff331ec5be9c84883eb0e84f700d605ef30152ae", "5221032c6c755d5da9c9e442bc4fdd08680d27e52b55bdefe8f664e7df2726686a2bf72103a0b2c4d3286d5ce538c93bb578e8b25f8e685618d6c0304ec6556393ad873b4c52ae", "5221032c6c755d5da9c9e442bc4fdd08680d27e52b55bdefe8f664e7df2726686a2bf72102536c74016e54a5023160960fa739cadf8f031d78d9cb0ceb7922c174cd4e7c2a52ae", "5221032c6c755d5da9c9e442bc4fdd08680d27e52b55bdefe8f664e7df2726686a2bf721032a1f697a7bc0b6feaa036e7f08d2ff7674f9dbc3e17ef930d1f7ec10755bc5f852ae", "5221032c6c755d5da9c9e442bc4fdd08680d27e52b55bdefe8f664e7df2726686a2bf721034a502facb54118ed072abab32321665bd3ed609fe2a5f63aa687a8a55205efa852ae", "5221032c6c755d5da9c9e442bc4fdd08680d27e52b55bdefe8f664e7df2726686a2bf72103c287f5d86aac6156b7368fe3c474cef5d9e27e4a0580b55a822ed83e65c43e9852ae", "5221032c6c755d5da9c9e442bc4fdd08680d27e52b55bdefe8f664e7df2726686a2bf72103a438065c6dd6c1db7bbd1077828cddb8d1f1322bc21df530214c495d681d19ac52ae", "5221032c6c755d5da9c9e442bc4fdd08680d27e52b55bdefe8f664e7df2726686a2bf72103bc1ba670f47c239bd567f5ffe733e90250b26d21b5d5f35f9aa119081efd4d8d52ae", "5221032c6c755d5da9c9e442bc4fdd08680d27e52b55bdefe8f664e7df2726686a2bf721028bc9fd70333fd6ae9205aed42de5e37ac17b82dc386bdc0d0dec3bca1a28f5c052ae", "5221032c6c755d5da9c9e442bc4fdd08680d27e52b55bdefe8f664e7df2726686a2bf721029770d82c16ef9388620430b14f4c7f078cc456bd5c2c76cb039c9aa67034512d52ae"] 
    
    tx, siglist = OnChain::Transaction.create_transaction(
      redemption_scripts, 'myDsUrM5Sd7SjpnWXnQARyTriVAPfLQbt8', 4000000, 10000, :testnet3)
      
    puts tx
    
    puts siglist
  end
  
end