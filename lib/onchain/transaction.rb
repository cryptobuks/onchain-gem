class OnChain::Transaction
  class << self
    
    MINERS_BYTE_FEE = 100
    CACHE_KEY = 'Bitcoin21Fees'
    CACHE_FOR = 10 # 10 minutes, roughly each block.
      
    def calculate_miners_fee(addresses, amount, network = :bitcoin)
      
      tx_size = estimate_transaction_size(addresses, amount, network)
      
      tx_fee = get_recommended_tx_fee["fastestFee"]
      
      return tx_size * tx_fee
      
    end
    
    def get_recommended_tx_fee
      
      begin
      
        if OnChain::BlockChain.cache_read(CACHE_KEY) == nil
          fees = OnChain::BlockChain.fetch_response('https://bitcoinfees.21.co/api/v1/fees/recommended', true)
          OnChain::BlockChain.cache_write(CACHE_KEY, fees, CACHE_FOR)
        end
        
        return OnChain::BlockChain.cache_read(CACHE_KEY)
      rescue
        fees = {"fastestFee" => 200,"halfHourFee" => 180,"hourFee" => 160}
        OnChain::BlockChain.cache_write(CACHE_KEY, fees, CACHE_FOR)
        return OnChain::BlockChain.cache_read(CACHE_KEY)
      end
    end
    
    # http://bitcoin.stackexchange.com/questions/1195/how-to-calculate-transaction-size-before-sending
    # in*148 + out*34 + 10 plus or minus 'in'
    def estimate_transaction_size(addresses, amount, network = :bitcoin)
      
      unspents, indexes, change = OnChain::BlockChain.get_unspent_for_amount(addresses, amount, network)
      indexes ,change = nil
      
      # Assume each input is 275 bytes.
      size_in_bytes = unspents.count * 180
      
      # Add on 3 outputs of assumed size 50 bytes.
      size_in_bytes = size_in_bytes + (3 * 34)
      
      # Add on 50 bytes for good luck
      size_in_bytes += unspents.count
      
      size_in_bytes += 10
      
      return size_in_bytes
      
    end
    
    # Once a transaction is created we rip it aaprt again to make sure it is not
    # overspending the users funds.
    def interrogate_transaction(txhex, wallet_addresses, fee_addresses, 
      total_to_send, network = :bitcoin)
      
      tx_bin = txhex.scan(/../).map { |x| x.hex }.pack('c*')
      tx_to_sign = Bitcoin::Protocol::Tx.new(tx_bin)
      
      primary_send = 0
      our_fees = 0
      unrecognised_destination = 0
      total_change = 0
      miners_fee = 0
      address = ''
      
      tx_to_sign.out.each do |txout|
        
        dest = get_address_from_script(Bitcoin::Script.new(txout.script), network)
        
        #@total_to_send += txout.value
        
        # Is it the users key i.e. a change address
        if wallet_addresses.include? dest 
          total_change += txout.value
        else
          # The first address in the TX is the one the user wants to pay.
          if address == '' or address == dest
            primary_send += txout.value
            address = dest
          elsif fee_addresses.include? dest
            our_fees += txout.value
          else
            unrecognised_destination += txout.value
          end
        end
      end
      
      miners_fee = total_to_send - our_fees - primary_send - total_change
      total_change = total_change / 100000000.0
      total_to_send = total_to_send / 100000000.0
      our_fees = our_fees / 100000000.0
      unrecognised_destination = unrecognised_destination / 100000000.0
      miners_fee = miners_fee / 100000000.0
      primary_send = primary_send / 100000000.0
      
      return { miners_fee: miners_fee, total_change: total_change,
        total_to_send: total_to_send, our_fees: our_fees,
        destination: address, unrecognised_destination: unrecognised_destination, 
        primary_send: primary_send 
      }
    
    end
    
    # Check a transactions inputs only spend enough to cover fees and amount
    # Basically if onchain creates an incorrect transaction the client
    # can identify it here.
    def check_integrity(txhex, amount, orig_addresses, dest_addr, tolerence)
      
      tx = Bitcoin::Protocol::Tx.new OnChain::hex_to_bin(txhex)
      
      input_amount = 0
      # Let's add up the value of all the inputs.
      tx.in.each_with_index do |txin, index|
      
        prev_hash = txin.to_hash['prev_out']['hash']
        prev_index = txin.to_hash['prev_out']['n']
        
        # Get the amount for the previous output
        prevhex = OnChain::BlockChain.get_transaction(prev_hash)
        prev_tx = Bitcoin::Protocol::Tx.new OnChain::hex_to_bin(prevhex)
        
        input_amount += prev_tx.out[prev_index].value
        
        if ! orig_addresses.include? prev_tx.out[prev_index].parsed_script.get_hash160_address
          raise "One of the inputs is not from from our list of valid originating addresses"
        end
      end
      
      # subtract the the chnage amounts
      tx.out.each do |txout|
        if orig_addresses.include? txout.parsed_script.get_address
          input_amount = input_amount - txout.value
        end
      end
      
      tolerence = (amount * (1 + tolerence)) 
      if input_amount > tolerence
        raise "Transaction has more input value (#{input_amount}) than the tolerence #{tolerence}"
      end
      
      return true
    end
    
    def create_single_address_transaction(orig_addr, dest_addr, amount, 
      fee_in_satoshi, fee_addr, miners_fee, network = :bitcoin)

      tx = Bitcoin::Protocol::Tx.new
      
      total_amount = amount + fee_in_satoshi + miners_fee
      
      unspents, indexes, change = OnChain::BlockChain.get_unspent_for_amount(
        [orig_addr], total_amount, network)
      indexes = nil
      
      total_input_value = 0
      # Process the unpsent outs.
      unspents.each_with_index do |spent, index|

        txin = Bitcoin::Protocol::TxIn.new([ spent[0] ].pack('H*').reverse, spent[1])
        txin.script_sig = OnChain.hex_to_bin(spent[2])
        total_input_value = total_input_value + spent[3].to_i
        tx.add_in(txin)
      end
      
      txout = Bitcoin::Protocol::TxOut.new(amount, to_address_script(dest_addr, network))
      tx.add_out(txout)
      
      # Add an output for the fee
      add_fee_to_tx(fee_in_satoshi, fee_addr, tx, network)
    
      # Send the change back.
      if change > 0
        
        txout = Bitcoin::Protocol::TxOut.new(change, to_address_script(orig_addr, network))
  
        tx.add_out(txout)
      end

      inputs_to_sign = get_inputs_to_sign(tx)
      
      return OnChain::bin_to_hex(tx.to_payload), inputs_to_sign, total_input_value
    end
    
    # Given a send address and an amount produce a transaction 
    # and a list of hashes that need to be signed.
    # 
    # The transaction will be in hex format.
    #
    # The list of hashes that need to be signed will be in this format
    #
    # [input index]{public_key => { :hash => hash} }
    #
    # i.e.
    #
    # [0][034000....][:hash => '345435345...'] 
    # [0][02fee.....][:hash => '122133445....']
    # 
    def create_transaction(redemption_scripts, address, amount_in_satoshi, 
      miners_fee, fee_in_satoshi, fee_addr, network = :bitcoin)
    
      total_amount = amount_in_satoshi + fee_in_satoshi + miners_fee
      
      addresses = redemption_scripts.map { |rs| 
        generate_address_of_redemption_script(rs, network)
      }
      
      unspents, indexes, change = OnChain::BlockChain.get_unspent_for_amount(addresses, total_amount, network)
      
      # OK, let's build a transaction.
      tx = Bitcoin::Protocol::Tx.new
      
      total_input_value = 0
      # Process the unpsent outs.
      unspents.each_with_index do |spent, index|

        script = redemption_scripts[indexes[index]]
        
        txin = Bitcoin::Protocol::TxIn.new([ spent[0] ].pack('H*').reverse, spent[1])
        txin.script_sig = OnChain::hex_to_bin(script)
        total_input_value = total_input_value + spent[3].to_i
        tx.add_in(txin)
      end

      # Add an output for the main transfer
      txout = Bitcoin::Protocol::TxOut.new(amount_in_satoshi, 
          to_address_script(address, network))
      tx.add_out(txout)
      
      # Add an output for the fee
      add_fee_to_tx(fee_in_satoshi, fee_addr, tx, network)
      
      change_address = addresses[0]
    
      # Send the change back.
      if change > 0
      
        txout = Bitcoin::Protocol::TxOut.new(change, 
          to_address_script(change_address, network))
  
        tx.add_out(txout)
      end

      inputs_to_sign = get_inputs_to_sign tx
    
      return OnChain::bin_to_hex(tx.to_payload), inputs_to_sign, total_input_value
    end
  
    # Given a transaction in hex string format, apply
    # the given signature list to it.
    #
    # Signatures should be in the format
    #
    # [0]{034000.....' => {'hash' => '345435345....', 'sig' => '435fgdf4553...'}}
    # [0]{02fee.....' => {'hash' => '122133445....', 'sig' => '435fgdf4553...'}}
    #
    # For transactions coming from non multi sig wallets we need to set
    # the pubkey parameter to the full public hex key of the address.
    def sign_transaction(transaction_hex, sig_list, pubkey = nil)
      
      tx = Bitcoin::Protocol::Tx.new OnChain::hex_to_bin(transaction_hex)
      
      tx.in.each_with_index do |txin, index|
        
        sigs = []
        
        rscript = Bitcoin::Script.new txin.script
        
        pub_keys = get_public_keys_from_script(rscript)
        pub_keys.each do |hkey|
          
          if sig_list[index][hkey] != nil and sig_list[index][hkey]['sig'] != nil
            
            # Add the signature to the list.
            sigs << OnChain.hex_to_bin(sig_list[index][hkey]['sig'])
            
          end
        end
        
        if sigs.count > 0
          in_script = Bitcoin::Script.new txin.script
          if in_script.is_hash160?
            sig = sigs[0]
            txin.script = Bitcoin::Script.to_pubkey_script_sig(sig, OnChain.hex_to_bin(pubkey))
          else
            
            # I replace the call to Bitcoin::Script.to_p2sh_multisig_script_sig
            # as it didn't work for my smaller 2 of 2 redemption scripts
            sig_script = '00'
            sigs.each do |sigg|
              sigg << 1
              sig_script += sigg.length.to_s(16)
              sig_script += OnChain.bin_to_hex(sigg)
            end
            if rscript.to_payload.length < 76
              sig_script += rscript.to_payload.length.to_s(16)
              sig_script += OnChain.bin_to_hex(rscript.to_payload)
            else
              sig_script += 76.to_s(16)
              sig_script += rscript.to_payload.length.to_s(16)
              sig_script += OnChain.bin_to_hex(rscript.to_payload)
            end
              
            txin.script = OnChain.hex_to_bin(sig_script)
          end
        end
      
        #raise "Signature error " + index.to_s  if ! tx.verify_input_signature(index, in_script.to_payload)
      end
      
      return OnChain::bin_to_hex(tx.to_payload)
    end
    
    # Run through the signature list and check it is all signed.
    def do_we_have_all_the_signatures(sig_list)
      
      sig_list.each do |input|
        input.each_key do |public_key|
          if input[public_key]['hash'] == nil or input[public_key]['sig'] == nil
            return false
          end
        end
      end
      
      return true
    end
    
    private
    
    def add_fee_to_tx(fee, fee_addr, tx, network = :bitcoin)
      
      # Add wallet fee
      if fee > 0 
        
        # Check for affiliate
        if fee_addr.kind_of?(Array)
          affil_fee = fee / 2
          txout1 = Bitcoin::Protocol::TxOut.new(affil_fee, to_address_script(fee_addr[0], network))
          txout2 = Bitcoin::Protocol::TxOut.new(affil_fee, to_address_script(fee_addr[1], network))
          tx.add_out(txout1)
          tx.add_out(txout2)
        else
          txout = Bitcoin::Protocol::TxOut.new(fee, to_address_script(fee_addr, network))
          tx.add_out(txout)
        end
      end
      
    end
    
    # This runs when we are decoding a transaction
    def get_address_from_script(script, network)
      
      if script.is_p2sh?
        p2sh_version = Bitcoin::NETWORKS[network][:p2sh_version]
        return Bitcoin.encode_address script.get_hash160, p2sh_version
      else
        address_version = Bitcoin::NETWORKS[network][:address_version]
        return Bitcoin.encode_address(script.get_hash160, address_version)
      end
    end
    
    def get_public_keys_from_script(script)
  
      if script.is_hash160?
        return [Bitcoin.hash160_to_address(script.get_hash160)]
      end
      
      pubs = []
      script.get_multisig_pubkeys.each do |pub|
        pubs << OnChain.bin_to_hex(pub)
      end
      return pubs
    end
    
    def get_inputs_to_sign(tx)
      inputs_to_sign = []
      tx.in.each_with_index do |txin, index|
        hash = tx.signature_hash_for_input(index, txin.script, 1)
        
        script = Bitcoin::Script.new txin.script
        
        pubkeys = get_public_keys_from_script(script)
        pubkeys.each do |key|
          
          if inputs_to_sign[index] == nil
            inputs_to_sign[index] = {}
          end
          inputs_to_sign[index][key] = {'hash' => OnChain::bin_to_hex(hash)}
        end
      end
      return inputs_to_sign
    end
  
    def generate_address_of_redemption_script(script, network = :bitcoin)
      
      p2sh_version = Bitcoin::NETWORKS[network][:p2sh_version]
      address = Bitcoin.encode_address(Bitcoin.hash160(script), p2sh_version)
      
      return address
    end
  
    # This was created as the method in bitcoin ruby was not network aware.
    def to_address_script(address, network_to_use = :bitcoin)
      
      size = Bitcoin::NETWORKS[network_to_use][:p2sh_version].length
      
      address_type = :hash160
      if Bitcoin.decode_base58(address)[0...size] == Bitcoin::NETWORKS[network_to_use][:p2sh_version].downcase
        address_type = :p2sh
      end
      
      hash160 = Bitcoin.decode_base58(address)[size...(40 + size)]
      
      case address_type
      when :hash160; Bitcoin::Script.to_hash160_script(hash160)
      when :p2sh;    Bitcoin::Script.to_p2sh_script(hash160)
      end
    end
      
  end
end