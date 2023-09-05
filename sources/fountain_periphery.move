module kriya_fountain::fountain_periphery {
   
    use sui::tx_context::{Self, TxContext};
    use sui::clock::Clock;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::balance;
    use kriya_fountain::fountain_core::{Self as core, Fountain, StakeProof, AdminCap};
    use kriya::spot_dex::KriyaLPToken;

    public entry fun create_fountain<A, B, R>(
        init_token: KriyaLPToken<A, B>,
        flow_amount: u64,
        flow_interval: u64,
        min_lock_time: u64,
        max_lock_time: u64,
        start_time: u64,
        with_admin_cap: bool,
        ctx: &mut TxContext,
    ) {
        if (with_admin_cap) {
            let (fountain, admin_cap)= core::new_fountain_with_admin_cap<A, B, R>(
                init_token,
                flow_amount,
                flow_interval,
                min_lock_time,
                max_lock_time,
                start_time,
                ctx,
            );
            transfer::public_share_object(fountain);
            transfer::public_transfer(admin_cap, tx_context::sender(ctx));
        } else {
            let fountain = core::new_fountain<A, B, R>(
                init_token,
                flow_amount,
                flow_interval,
                min_lock_time,
                max_lock_time,
                start_time,
                ctx,
            );
            transfer::public_share_object(fountain);
        }
    }

    public entry fun setup_fountain<A, B, R>(
        clock: &Clock,
        init_supply: Coin<R>,
        init_token: KriyaLPToken<A, B>,
        flow_amount: u64,
        flow_interval: u64,
        min_lock_time: u64,
        max_lock_time: u64,
        start_time: u64,
        with_admin_cap: bool,
        ctx: &mut TxContext,
    ) {
        if (with_admin_cap) {
            let (fountain, admin_cap) = core::new_fountain_with_admin_cap<A, B, R>(
                init_token,
                flow_amount,
                flow_interval,
                min_lock_time,
                max_lock_time,
                start_time,
                ctx,
            );
            let init_supply = coin::into_balance(init_supply);
            core::supply(clock, &mut fountain, init_supply);
            transfer::public_share_object(fountain);
            transfer::public_transfer(admin_cap, tx_context::sender(ctx));
        } else {
            let fountain = core::new_fountain<A, B, R>(
                init_token,
                flow_amount,
                flow_interval,
                min_lock_time,
                max_lock_time,
                start_time,
                ctx,
            );
            let init_supply = coin::into_balance(init_supply);
            core::supply(clock, &mut fountain, init_supply);
            transfer::public_share_object(fountain);
        }
    }

    public entry fun create_penalty_vault<A, B, R>(
        admin_cap: &AdminCap,
        fountain: &mut Fountain<A, B, R>,
        init_token: KriyaLPToken<A, B>,
        max_penalty_rate: u64,
    ) {
        core::new_penalty_vault(admin_cap, fountain, init_token, max_penalty_rate);
    }

    public entry fun supply<A, B, R>(clock: &Clock, fountain: &mut Fountain<A, B, R>, resource: Coin<R>) {
        let resource = coin::into_balance(resource);
        core::supply(clock, fountain, resource);
    }

    public entry fun airdrop<A, B, R>(fountain: &mut Fountain<A, B, R>, resource: Coin<R>) {
        let resource = coin::into_balance(resource);
        core::airdrop(fountain, resource);
    }

    public entry fun tune<A, B, R>(fountain: &mut Fountain<A, B, R>, resource: Coin<R>) {
        let resource = coin::into_balance(resource);
        core::tune(fountain, resource);
    }

    public entry fun stake<A, B, R>(
        clock: &Clock,
        fountain: &mut Fountain<A, B, R>,
        input: KriyaLPToken<A, B>,
        lock_time: u64,
        ctx: &mut TxContext,
    ) {
        let proof = core::stake(clock, fountain, input, lock_time, ctx);
        transfer::public_transfer(proof, tx_context::sender(ctx));
    }

    public entry fun claim<A, B, R>(
        clock: &Clock,
        fountain: &mut Fountain<A, B, R>,
        proof: &mut StakeProof<A, B, R>,
        ctx: &mut TxContext,
    ) {
        let reward = core::claim(clock, fountain, proof);
        if (balance::value(&reward) > 0) {
            let reward = coin::from_balance(reward, ctx);
            transfer::public_transfer(reward, tx_context::sender(ctx));
        } else {
            balance::destroy_zero(reward);
        };
    }

    public entry fun unstake<A, B, R>(
        clock: &Clock,
        fountain: &mut Fountain<A, B, R>,
        proof: StakeProof<A, B, R>,
        ctx: &mut TxContext,
    ) {
        let (unstake_output, reward) = core::unstake(clock, fountain, proof, ctx);
        let sender = tx_context::sender(ctx);
        transfer::public_transfer(unstake_output, sender);
        if (balance::value(&reward) > 0) {
            let reward = coin::from_balance(reward, ctx);
            transfer::public_transfer(reward, sender);
        } else {
            balance::destroy_zero(reward);
        };
    }

    public entry fun force_unstake<A, B, R>(
        clock: &Clock,
        fountain: &mut Fountain<A, B, R>,
        proof: StakeProof<A, B, R>,
        ctx: &mut TxContext,
    ) {
        let (unstake_output, reward) = core::force_unstake(clock, fountain, proof, ctx);
        let sender = tx_context::sender(ctx);
        transfer::public_transfer(unstake_output, sender);
        if (balance::value(&reward) > 0) {
            let reward = coin::from_balance(reward, ctx);
            transfer::public_transfer(reward, sender);
        } else {
            balance::destroy_zero(reward);
        }        
    }

    public entry fun claim_penalty<A, B, R>(
        admin_cap: &AdminCap,
        fountain: &mut Fountain<A, B, R>,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        let penalty = core::claim_penalty(admin_cap, fountain, ctx);
        transfer::public_transfer(penalty, recipient);
    }
}