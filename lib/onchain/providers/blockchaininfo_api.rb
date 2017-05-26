class OnChain::BlockChain
  class << self
  
    def blockinfo_address_history(address, network = :bitcoin)
      
      base_url = "https://blockchain.info/address/#{address}?format=json"
      
      base_url = base_url + get_api_key_params
      
      json = fetch_response(base_url, true)
      
      blockinfo_parse_address_tx(address, json)
    end
    
    def get_api_key_params
      if ENV['BLOCKCHAIN_INFO_API_KEY'] != nil
        return "&api_code=#{ENV['BLOCKCHAIN_INFO_API_KEY']}"
      end
      return ""
    end

    def blockinfo_get_history_for_addresses(addresses, network = :bitcoin)
      history = []
      addresses.each do |address|
        res = blockinfo_address_history(address, network)
        res.each do |r|
          history << r
        end
      end
      return history
    end
    
    def blockinfo_parse_address_tx(address, json)
      
      hist = []
      if json.key?('txs')
        txs = json['txs']
        txs.each do |tx|
          row = {}
          row[:time] = tx["time"]
          row[:addr] = {}
          row[:outs] = {}
          inputs = tx['inputs']
          val = 0
          recv = "Y"
          inputs.each do |input|
            if input["prev_out"] != nil and input["prev_out"]["addr"] != nil
              row[:addr][input["prev_out"]["addr"]] = input["prev_out"]["addr"]
              if input["prev_out"]["addr"] == address
                recv = "N"
              end
            end
          end
          tx["out"].each do |out|
            if out['addr'] != nil
              row[:outs][out["addr"]] = out["addr"]
              if recv == "Y" and out["addr"] == address
                val = val + out["value"].to_f / 100000000.0
              elsif recv == "N" and out["addr"] != address
                val = val + out["value"].to_f / 100000000.0
              end
            end
          end
          row[:total] = val
          row[:recv] = recv
          row[:hash] = tx["hash"]
          row[:block_height] = tx["block_height"]
          hist << row
        end
        return hist
      else
        'Error'
      end
      return hist
    end

    def blockinfo_get_address_info(address, network = :bitcoin)
      
      base = "https://blockchain.info/multiaddr?&simple=true&active=" + address
      
      base = base + get_api_key_params
      
      json = fetch_response(URI::encode(base))
      
      return { received: json[address]['total_received'], 
        balance: json[address]['final_balance'],
        confirmed: json[address]['final_balance'] }
      
    end

    def blockinfo_get_all_balances(addresses, network = :bitcoin)
      base = "https://blockchain.info/multiaddr?&simple=true&active="
      
      addr = get_uncached_addresses(addresses)
      
      if addr.length == 0
        return
      end
      
      addr.each do |address|
        base = base + address + '|'
      end
      
      base = base + get_api_key_params
      
      json = fetch_response(URI::encode(base))
      
      addresses.each do |address|
        bal = json[address]['final_balance'] / 100000000.0
        cache_write(address, bal, BALANCE_CACHE_FOR)
      end
    end

    def blockinfo_get_unspent_outs(address, network = :bitcoin)
      base_url = "https://blockchain.info/unspent?active=#{address}"
      
      base_url = base_url + get_api_key_params
      
      json = fetch_response(base_url, true)
      
      unspent = []
      
      json['unspent_outputs'].each do |data|
        line = []
        line << reverse_blockchain_tx(data['tx_hash'])
        line << data['tx_output_n']
        line << data['script']
        line << data['value']
        unspent << line
      end
      
      return unspent
    end

    def blockinfo_get_balance(address, network = :bitcoin)
      if cache_read(address) == nil
        json = block_chain('address', address, "&limit=0")
        if json.key?('final_balance')
          bal = json['final_balance'] / 100000000.0
          cache_write(address, bal, BALANCE_CACHE_FOR)
        else
          cache_write(address, 'Error', BALANCE_CACHE_FOR)
        end
      end
      bal = cache_read(address)
      if bal.class == Fixnum
        bal = bal.to_f
      end
      return bal
    end

    def blockinfo_get_transaction(txhash)
      base = "https://blockchain.info/rawtx/#{txhash}?format=hex"
      
      base = base + get_api_key_params
      
      return fetch_response(URI::encode(base), false)
    end
  
    def block_chain(cmd, address, params = "")
      base_url = "https://blockchain.info/#{cmd}/#{address}?format=json" + params
      
      base_url = base_url + get_api_key_params
      
      fetch_response(base_url, true)
    end
    
    def reverse_blockchain_tx(hash)
       bytes = hash.scan(/../).map { |x| x.hex.chr }.join
       
       bytes = bytes.reverse
       
       return hash.scan(/../).reverse.join
    end
    
  end
end