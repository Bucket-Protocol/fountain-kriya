module kriya_fountain::fountain_core {

    use sui::balance::{Self, Balance};
    use sui::tx_context::TxContext;
    use sui::object::{Self, ID, UID};
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::dynamic_field as df;
    use bucket_fountain::math;
    use kriya::spot_dex::{Self, KriyaLPToken};

    const DISTRIBUTION_PRECISION: u128 = 0x10000000000000000;
    const PENALTY_RATE_PRECISION: u64 = 1_000_000;

    const EStillLocked: u64 = 0;
    const EInvalidProof: u64 = 1;
    const ENotLocked:  u64 = 2;
    const EInvalidAdminCap: u64 = 3;
    const EAlreadyHasPenaltyVault: u64 = 4;
    const EPenaltyVaultNotExists: u64 = 5;
    const EInvalidMaxPenaltyRate: u64 = 6;

    struct AdminCap has key, store {
        id: UID,
        fountain_id: ID,
    }

    struct Fountain<phantom A, phantom B, phantom R> has store, key {
        id: UID,
        source: Balance<R>,
        flow_amount: u64,
        flow_interval: u64,
        pool: Balance<R>,
        staked: KriyaLPToken<A, B>,
        total_weight: u64,
        cumulative_unit: u128,
        latest_release_time: u64,
        min_lock_time: u64,
        max_lock_time: u64,
    }

    struct StakeProof<phantom A, phantom B, phantom R> has store, key {
        id: UID,
        fountain_id: ID,
        stake_amount: u64,
        start_uint: u128,
        stake_weight: u64,
        lock_until: u64,
    }

    struct PenaltyKey has store, copy, drop {}

    struct PenaltyVault<phantom A, phantom B> has store {
        max_penalty_rate: u64,
        vault: KriyaLPToken<A, B>,
    }

    struct StakeEvent<phantom A, phantom B, phantom R> has copy, drop {
        fountain_id: ID,
        stake_amount: u64,
        stake_weight: u64,
        lock_time: u64,
        start_time: u64,
    }

    struct ClaimEvent<phantom A, phantom B, phantom R> has copy, drop {
        fountain_id: ID,
        reward_amount: u64,
        claim_time: u64,
    }

    struct UnstakeEvent<phantom A, phantom B, phantom R> has copy, drop {
        fountain_id: ID,
        unstake_amount: u64,
        unstake_weight: u64,
        end_time: u64,
    }

    struct PenaltyEvent<phantom A, phantom B> has copy, drop {
        fountain_id: ID,
        penalty_amount: u64,
    }

    public fun new_fountain<A, B, R>(
        init_token: KriyaLPToken<A, B>,
        flow_amount: u64,
        flow_interval: u64,
        min_lock_time: u64,
        max_lock_time: u64,
        start_time: u64,
        ctx: &mut TxContext,
    ): Fountain<A, B, R> {
        Fountain {
            id: object::new(ctx),
            source: balance::zero(),
            flow_amount,
            flow_interval,
            pool: balance::zero(),
            staked: init_token,
            total_weight: 0,
            cumulative_unit: 0,
            latest_release_time: start_time,
            min_lock_time,
            max_lock_time,
        }
    }

    public fun new_fountain_with_admin_cap<A, B, R>(
        init_token: KriyaLPToken<A, B>,
        flow_amount: u64,
        flow_interval: u64,
        min_lock_time: u64,
        max_lock_time: u64,
        start_time: u64,
        ctx: &mut TxContext,
    ): (Fountain<A, B, R>, AdminCap) {
        let fountain = new_fountain<A, B, R>(init_token, flow_amount, flow_interval, min_lock_time, max_lock_time, start_time, ctx);
        let fountain_id = object::id(&fountain);
        let admin_cap = AdminCap { id: object::new(ctx), fountain_id };
        (fountain, admin_cap)
    }

    public fun new_penalty_vault<A, B, R>(
        admin_cap: &AdminCap,
        fountain: &mut Fountain<A, B, R>,
        init_token: KriyaLPToken<A, B>,
        max_penalty_rate: u64,

    ) {
        check_admin_cap(admin_cap, fountain);
        assert!(max_penalty_rate <= PENALTY_RATE_PRECISION, EInvalidMaxPenaltyRate);
        let penalty_key = PenaltyKey {};
        assert!(
            !df::exists_with_type<PenaltyKey, PenaltyVault<A, B>>(
                &fountain.id,
                penalty_key,
            ),
            EAlreadyHasPenaltyVault,
        );
        df::add(
            &mut fountain.id,
            penalty_key,
            PenaltyVault {
                max_penalty_rate,
                vault: init_token,
            }
        );
    }

    public fun supply<A, B, R>(clock: &Clock, fountain: &mut Fountain<A, B, R>, resource: Balance<R>) {
        source_to_pool(fountain, clock);
        balance::join(&mut fountain.source, resource);
    }

    public fun airdrop<A, B, R>(fountain: &mut Fountain<A, B, R>, resource: Balance<R>) {
        collect_resource(fountain, resource);
    }

    public fun tune<A, B, R>(fountain: &mut Fountain<A, B, R>, resource: Balance<R>) {
        balance::join(&mut fountain.pool, resource);
    }

    public fun stake<A, B, R>(
        clock: &Clock,
        fountain: &mut Fountain<A, B, R>,
        input: KriyaLPToken<A, B>,
        lock_time: u64,
        ctx: &mut TxContext,
    ): StakeProof<A, B, R> {
        source_to_pool(fountain, clock);
        let stake_amount = spot_dex::lp_token_value(&input);
        spot_dex::lp_token_join(&mut fountain.staked, input);
        let stake_weight = math::compute_weight(
            stake_amount,
            lock_time,
            fountain.min_lock_time,
            fountain.max_lock_time,
        );
        fountain.total_weight = fountain.total_weight + stake_weight;
        let fountain_id = object::id(fountain);
        let current_time = clock::timestamp_ms(clock);
        event::emit(StakeEvent<A, B, R> {
            fountain_id,
            stake_amount,
            stake_weight,
            lock_time,
            start_time: current_time,
        });
        StakeProof {
            id: object::new(ctx),
            fountain_id,
            stake_amount,
            start_uint: fountain.cumulative_unit,
            stake_weight,
            lock_until: current_time + lock_time,
        }
    }

    public fun claim<A, B, R>(
        clock: &Clock,
        fountain: &mut Fountain<A, B, R>,
        proof: &mut StakeProof<A, B, R>,
    ): Balance<R> {
        check_proof(fountain, proof);
        source_to_pool(fountain, clock);
        let fountain_id = proof.fountain_id;
        let reward_amount = (math::mul_factor_u128(
            (proof.stake_weight as u128),
            fountain.cumulative_unit - proof.start_uint,
            DISTRIBUTION_PRECISION,
            ) as u64);
        event::emit(ClaimEvent<A, B, R> {
            fountain_id,
            reward_amount,
            claim_time: clock::timestamp_ms(clock),
        });
        proof.start_uint = fountain.cumulative_unit;
        balance::split(&mut fountain.pool, reward_amount)
    }

    public fun unstake<A, B, R>(
        clock: &Clock,
        fountain: &mut Fountain<A, B, R>,
        proof: StakeProof<A, B, R>,
        ctx: &mut TxContext,
    ): (KriyaLPToken<A, B>, Balance<R>) {
        check_proof(fountain, &proof);
        source_to_pool(fountain, clock);
        let current_time = clock::timestamp_ms(clock);
        let reward = claim(clock, fountain, &mut proof);
        let StakeProof {
            id,
            fountain_id,
            stake_amount,
            start_uint: _,
            stake_weight,
            lock_until
        } = proof;
        assert!(current_time >= lock_until, EStillLocked);
        object::delete(id);
        fountain.total_weight = fountain.total_weight - stake_weight;
        event::emit(UnstakeEvent<A, B, R> {
            fountain_id,
            unstake_amount: stake_amount,
            unstake_weight: stake_weight,
            end_time: current_time,
        });
        let returned_stake = spot_dex::lp_token_split(&mut fountain.staked, stake_amount, ctx);
        (returned_stake, reward)
    }

    public fun force_unstake<A, B, R>(
        clock: &Clock,
        fountain: &mut Fountain<A, B, R>,
        proof: StakeProof<A, B, R>,
        ctx: &mut TxContext,
    ): (KriyaLPToken<A, B>, Balance<R>) {
        check_proof(fountain, &proof);
        source_to_pool(fountain, clock);
        let current_time = clock::timestamp_ms(clock);
        let reward = claim(clock, fountain, &mut proof);
        let penalty_amount = get_penalty_amount(fountain, &proof, current_time);
        let StakeProof {
            id,
            fountain_id,
            stake_amount,
            start_uint: _,
            stake_weight,
            lock_until: _,
        } = proof;
        object::delete(id);
        fountain.total_weight = fountain.total_weight - stake_weight;
        let returned_stake = spot_dex::lp_token_split(&mut fountain.staked, stake_amount, ctx);
        let penalty = spot_dex::lp_token_split(&mut returned_stake, penalty_amount, ctx);
        let penalty_vault = borrow_mut_penalty_vault(fountain);
        spot_dex::lp_token_join(&mut penalty_vault.vault, penalty);
        event::emit(UnstakeEvent<A, B, R> {
            fountain_id,
            unstake_amount: spot_dex::lp_token_value(&returned_stake),
            unstake_weight: stake_weight,
            end_time: current_time,
        });
        if (penalty_amount > 0) {
            event::emit(PenaltyEvent<A, B> {
                fountain_id,
                penalty_amount,
            });
        };
        (returned_stake, reward)
    }

    public entry fun update_flow_rate<A, B, R>(
        admin_cap: &AdminCap,
        clock: &Clock,
        fountain: &mut Fountain<A, B, R>,
        flow_amount: u64,
        flow_interval: u64
    ) {
        check_admin_cap(admin_cap, fountain);
        source_to_pool(fountain, clock);
        fountain.flow_amount = flow_amount;
        fountain.flow_interval = flow_interval;
    }

    public entry fun update_max_penalty_rate<A, B, R>(
        admin_cap: &AdminCap,
        fountain: &mut Fountain<A, B, R>,
        max_penalty_rate: u64,
    ) {
        check_admin_cap(admin_cap, fountain);
        let penaly_vault = borrow_mut_penalty_vault(fountain);
        penaly_vault.max_penalty_rate = max_penalty_rate;
    }

    public fun claim_penalty<A, B, R>(
        admin_cap: &AdminCap,
        fountain: &mut Fountain<A, B, R>,
        ctx: &mut TxContext,
    ): KriyaLPToken<A, B> {
        check_admin_cap(admin_cap, fountain);
        let penalty_key = PenaltyKey {};
        assert!(
            df::exists_with_type<PenaltyKey, PenaltyVault<A, B>>(
                &fountain.id,
                penalty_key,
            ),
            EPenaltyVaultNotExists,
        );
        let penalty_vault = df::borrow_mut<PenaltyKey, PenaltyVault<A, B>>(
            &mut fountain.id,
            penalty_key,
        );
        let penalty_balance = spot_dex::lp_token_value(&penalty_vault.vault);
        spot_dex::lp_token_split(&mut penalty_vault.vault, penalty_balance, ctx)
    }

    public fun get_flow_rate<A, B, R>(fountain: &Fountain<A, B, R>): (u64, u64) {
        (fountain.flow_amount, fountain.flow_interval)
    }

    public fun get_lock_time_range<A, B, R>(fountain: &Fountain<A, B, R>): (u64, u64) {
        (fountain.min_lock_time, fountain.max_lock_time)
    }

    public fun get_source_balance<A, B, R>(fountain: &Fountain<A, B, R>): u64 {
        balance::value(&fountain.source)
    }

    public fun get_pool_balance<A, B, R>(fountain: &Fountain<A, B, R>): u64 {
        balance::value(&fountain.pool)
    }

    public fun get_staked_balance<A, B, R>(fountain: &Fountain<A, B, R>): u64 {
        spot_dex::lp_token_value(&fountain.staked)
    }

    public fun get_total_weight<A, B, R>(fountain: &Fountain<A, B, R>): u64 {
        fountain.total_weight
    }

    public fun get_cumulative_unit<A, B, R>(fountain: &Fountain<A, B, R>): u128 {
        fountain.cumulative_unit
    }

    public fun get_max_penalty_rate<A, B, R>(fountain: &Fountain<A, B, R>): u64 {
        let penalty_vault = borrow_penalty_vault(fountain);
        penalty_vault.max_penalty_rate
    }

    public fun get_penalty_vault_balance<A, B, R>(fountain: &Fountain<A, B, R>): u64 {
        let penalty_vault = borrow_penalty_vault(fountain);
        spot_dex::lp_token_value(&penalty_vault.vault)
    }

    public fun get_proof_stake_amount<A, B, R>(proof: &StakeProof<A, B, R>): u64 {
        proof.stake_amount
    }

    public fun get_proof_stake_weight<A, B, R>(proof: &StakeProof<A, B, R>): u64 {
        proof.stake_weight
    }

    public fun get_proof_lock_until<A, B, R>(proof: &StakeProof<A, B, R>): u64 {
        proof.lock_until
    }

    public fun get_latest_release_time<A, B, R>(fountain: &Fountain<A, B, R>): u64 {
        fountain.latest_release_time
    }

    public fun get_reward_amount<A, B, R>(
        fountain: &Fountain<A, B, R>,
        proof: &StakeProof<A, B, R>,
        current_time: u64,
    ): u64 {
        let virtual_released_amount = get_virtual_released_amount(fountain, current_time);
        let virtual_cumulative_unit = fountain.cumulative_unit + math::mul_factor_u128(
            (virtual_released_amount as u128),
            DISTRIBUTION_PRECISION,
            (fountain.total_weight as u128)
        );
        (math::mul_factor_u128((proof.stake_weight as u128), virtual_cumulative_unit - proof.start_uint, DISTRIBUTION_PRECISION) as u64)
    }

    public fun get_penalty_amount<A, B, R>(
        fountain: &Fountain<A, B, R>,
        proof: &StakeProof<A, B, R>,
        current_time: u64,
    ): u64 {
        check_proof(fountain, proof);
        if (current_time >= proof.lock_until) {
            0
        } else {
            let max_penalty_rate = get_max_penalty_rate(fountain);
            let penalty_cap_amount = mul(
                proof.stake_amount,
                max_penalty_rate,
                PENALTY_RATE_PRECISION
            );
            let penalty_weight = mul(
                proof.stake_amount,
                proof.lock_until - current_time,
                fountain.max_lock_time,
            );
            mul(penalty_cap_amount, penalty_weight, proof.stake_weight)
        }
    }

    public fun get_virtual_released_amount<A, B, R>(fountain: &Fountain<A, B, R>, current_time: u64): u64 {
        if (current_time > fountain.latest_release_time) {
            let interval = current_time - fountain.latest_release_time;
            let released_amount = math::mul_factor(
                fountain.flow_amount,
                interval, 
                fountain.flow_interval,
            );
            let source_balance = get_source_balance(fountain);
            if (released_amount > source_balance) {
                released_amount = source_balance;
            };
            released_amount
        } else {
            0
        }
    }

    fun release_resource<A, B, R>(fountain: &mut Fountain<A, B, R>, clock: &Clock): Balance<R> {
        let current_time = clock::timestamp_ms(clock);
        if (current_time > fountain.latest_release_time) {
            let interval = current_time - fountain.latest_release_time;
            let released_amount = math::mul_factor(
                fountain.flow_amount,
                interval, 
                fountain.flow_interval,
            );
            let source_balance = get_source_balance(fountain);
            if (released_amount > source_balance) {
                released_amount = source_balance;
            };
            fountain.latest_release_time = current_time;
            balance::split(&mut fountain.source, released_amount)
        } else {
            balance::zero()
        }
    }

    fun collect_resource<A, B, R>(fountain: &mut Fountain<A, B, R>, resource: Balance<R>) {
        let resource_amount = balance::value(&resource);
        if (resource_amount > 0) {
            balance::join(&mut fountain.pool, resource);
            fountain.cumulative_unit = fountain.cumulative_unit + math::mul_factor_u128(
                (resource_amount as u128),
                DISTRIBUTION_PRECISION,
                (fountain.total_weight as u128)
            );
        } else {
            balance::destroy_zero(resource);
        };
    }

    fun source_to_pool<A, B, R>(fountain: &mut Fountain<A, B, R>, clock: &Clock) {
        if (get_source_balance(fountain) > 0) {
            let resource = release_resource(fountain, clock);
            collect_resource(fountain, resource);
        } else {
            let current_time = clock::timestamp_ms(clock);
            if (current_time > fountain.latest_release_time) {
                fountain.latest_release_time = current_time;
            };
        }
    }

    fun borrow_penalty_vault<A, B, R>(fountain: &Fountain<A, B, R>): &PenaltyVault<A, B> {
        let penalty_key = PenaltyKey {};
        assert!(
            df::exists_with_type<PenaltyKey, PenaltyVault<A, B>>(
                &fountain.id,
                penalty_key,
            ),
            EPenaltyVaultNotExists,
        );
        df::borrow<PenaltyKey, PenaltyVault<A, B>>(
            &fountain.id,
            penalty_key,
        )
    }

    fun borrow_mut_penalty_vault<A, B, R>(fountain: &mut Fountain<A, B, R>): &mut PenaltyVault<A, B> {
        let penalty_key = PenaltyKey {};
        assert!(
            df::exists_with_type<PenaltyKey, PenaltyVault<A, B>>(
                &fountain.id,
                penalty_key,
            ),
            EPenaltyVaultNotExists,
        );
        df::borrow_mut<PenaltyKey, PenaltyVault<A, B>>(
            &mut fountain.id,
            penalty_key,
        )
    }

    fun check_proof<A, B, R>(fountain: &Fountain<A, B, R>, proof: &StakeProof<A, B, R>) {
        assert!(object::id(fountain) == proof.fountain_id, EInvalidProof);
    }

    fun check_admin_cap<A, B, R>(admin_cap: &AdminCap, fountain: &Fountain<A, B, R>) {
        assert!(admin_cap.fountain_id == object::id(fountain), EInvalidAdminCap);
    }

    fun mul(x: u64, n: u64, m: u64): u64 {
        ((
            ((x as u128) * (n as u128) + (m as u128) / 2)
            / (m as u128)
        ) as u64)
    }

    #[test_only]
    public fun destroy_fountain_for_testing<A, B, R>(fountain: Fountain<A, B, R>) {
        let Fountain {
            id,
            source,
            flow_amount: _,
            flow_interval: _,
            pool,
            staked,
            total_weight: _,
            cumulative_unit: _,
            latest_release_time: _,
            min_lock_time: _,
            max_lock_time: _,
        } = fountain;
        object::delete(id);
        balance::destroy_for_testing(source);
        balance::destroy_for_testing(pool);
        spot_dex::destroy_for_testing(staked);
    }

    #[test_only]
    public fun destroy_proof_for_testing<A, B, R>(proof: StakeProof<A, B, R>) {
        let StakeProof {
            id,
            fountain_id: _,
            stake_amount: _,
            start_uint: _,
            stake_weight: _,
            lock_until: _ 
        } = proof;
        object::delete(id);
    }
}
