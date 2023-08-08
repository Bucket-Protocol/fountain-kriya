module kriya::spot_dex {
    
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin};
    use sui::tx_context::TxContext;

    struct LSP<phantom CoinA, phantom CoinB> has drop {}

    struct KriyaLPToken<phantom CoinA, phantom CoinB> has store, key {
	    id: UID,
	    pool_id: ID,
	    lsp: Coin<LSP<CoinA, CoinB>>
    }

    public fun lp_token_value<A, B>(token: &KriyaLPToken<A,B>): u64 {
        coin::value(&token.lsp)
    }

    public fun lp_token_join<A, B>(
        self: &mut KriyaLPToken<A,B>,
        token: KriyaLPToken<A,B>,
    ) {
        let KriyaLPToken { id, pool_id, lsp } = token;
        assert!(self.pool_id == pool_id, 0);
        object::delete(id);
        coin::join(&mut self.lsp, lsp);
    }

    public fun lp_token_split<A, B>(
        self: &mut KriyaLPToken<A,B>,
        amount: u64,
        ctx: &mut TxContext,
    ): KriyaLPToken<A,B> {
        KriyaLPToken {
            id: object::new(ctx),
            pool_id: self.pool_id,
            lsp: coin::split(&mut self.lsp, amount, ctx),
        }
    }

    #[test_only]
    use sui::balance;

    #[test_only]
    public fun new_for_testing<A, B>(
        pool_id: ID,
        lp_amount: u64,
        ctx: &mut TxContext,
    ): KriyaLPToken<A,B> {
        let lsp = balance::create_for_testing<LSP<A,B>>(lp_amount);
        let lsp = coin::from_balance(lsp, ctx);
        KriyaLPToken {
            id: object::new(ctx),
            pool_id,
            lsp,
        }
    }

    #[test_only]
    public fun destroy_for_testing<A, B>(token: KriyaLPToken<A, B>) {
        let KriyaLPToken { id, pool_id: _, lsp } = token;
        object::delete(id);
        let lsp = coin::into_balance(lsp);
        balance::destroy_for_testing(lsp);
    }
}