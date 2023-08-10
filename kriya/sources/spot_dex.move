module kriya::spot_dex {
    
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin};
    use sui::tx_context::TxContext;

    const EInvalidLPToken: u64 = 20;

    struct LSP<phantom X, phantom Y> has drop {}

    struct KriyaLPToken<phantom X, phantom Y> has store, key {
	    id: UID,
	    pool_id: ID,
	    lsp: Coin<LSP<X, Y>>
    }

    public fun lp_token_split<X, Y>(
        self: &mut KriyaLPToken<X, Y>,
        split_amount: u64,
        ctx: &mut TxContext
    ): KriyaLPToken<X, Y> {
        KriyaLPToken {
            id: object::new(ctx),
            pool_id: self.pool_id,
            lsp: coin::split(&mut self.lsp, split_amount, ctx)
        }
    }

    public fun lp_token_join<X, Y>(
        self: &mut KriyaLPToken<X, Y>,
        lp_token: KriyaLPToken<X, Y>
    ) {
        assert!(self.pool_id == lp_token.pool_id, EInvalidLPToken);
        let KriyaLPToken {id, pool_id: _, lsp} = lp_token;
        object::delete(id);
        coin::join(&mut self.lsp, lsp);
    }

    public fun lp_token_value<X, Y>(self: &KriyaLPToken<X, Y>): u64 {
        coin::value(&self.lsp)
    }

    public fun lp_destroy_zero<X, Y>(self: KriyaLPToken<X, Y>) {
        let KriyaLPToken {id, pool_id: _, lsp} = self;
        coin::destroy_zero(lsp);
        object::delete(id);
    }

    #[test_only]
    use sui::balance;

    #[test_only]
    public fun new_for_testing<X, Y>(
        pool_id: ID,
        lp_amount: u64,
        ctx: &mut TxContext,
    ): KriyaLPToken<X, Y> {
        let lsp = balance::create_for_testing<LSP<X, Y>>(lp_amount);
        let lsp = coin::from_balance(lsp, ctx);
        KriyaLPToken {
            id: object::new(ctx),
            pool_id,
            lsp,
        }
    }

    #[test_only]
    public fun destroy_for_testing<X, Y>(token: KriyaLPToken<X, Y>) {
        let KriyaLPToken { id, pool_id: _, lsp } = token;
        object::delete(id);
        let lsp = coin::into_balance(lsp);
        balance::destroy_for_testing(lsp);
    }
}