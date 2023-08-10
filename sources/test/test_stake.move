#[test_only]
module kriya_fountain::test_stake {

    use sui::sui::SUI;
    use sui::clock::Clock;
    use sui::test_scenario as ts;
    use kriya_fountain::test_coin_a::TEST_COIN_A;
    use kriya_fountain::test_coin_b::TEST_COIN_B;
    use bucket_fountain::math;
    use kriya_fountain::test_utils::{Self as ftu, pool_id};
    use kriya_fountain::fountain_core::{Self as fc, Fountain};
    use kriya_fountain::fountain_periphery as fp;
    use kriya::spot_dex;

    #[test]
    #[expected_failure(abort_code = math::EStakeAmountTooSmall)]
    fun test_stake_zero() {
        let flow_amount: u64 = 27_663_000_000_000;
        let flow_interval: u64 = 86400_000 * 7; // 1 week
        let min_lock_time: u64 = flow_interval * 5;
        let max_lock_time: u64 = flow_interval * 20;
        let scenario_val = ftu::setup<TEST_COIN_A, TEST_COIN_B, SUI>(
            flow_amount,
            flow_interval,
            min_lock_time,
            max_lock_time,
            false,
        );
        let scenario = &mut scenario_val;

        ts::next_tx(scenario, @0xcafe);
        {
            let clock = ts::take_shared<Clock>(scenario);
            let fountain = ts::take_shared<Fountain<TEST_COIN_A, TEST_COIN_B, SUI>>(scenario);
            let (min_lock_time, max_lock_time) = fc::get_lock_time_range(&fountain);
            let stake_input = spot_dex::new_for_testing<TEST_COIN_A, TEST_COIN_B>(pool_id(), 0, ts::ctx(scenario));
            let lock_time = (min_lock_time + max_lock_time) / 2;
            fp::stake(&clock, &mut fountain, stake_input, lock_time, ts::ctx(scenario));
            ts::return_shared(clock);
            ts::return_shared(fountain);
        };

        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = math::EInvalidLockTime)]
    fun test_lower_than_min_lock_time() {
        let flow_amount: u64 = 27_663_000_000_000;
        let flow_interval: u64 = 86400_000 * 7; // 1 week
        let min_lock_time: u64 = flow_interval * 5;
        let max_lock_time: u64 = flow_interval * 20;
        let scenario_val = ftu::setup<TEST_COIN_A, TEST_COIN_B, SUI>(
            flow_amount,
            flow_interval,
            min_lock_time,
            max_lock_time,
            false,
        );
        let scenario = &mut scenario_val;

        ts::next_tx(scenario, @0xcafe);
        {
            let clock = ts::take_shared<Clock>(scenario);
            let fountain = ts::take_shared<Fountain<TEST_COIN_A, TEST_COIN_B, SUI>>(scenario);
            let (min_lock_time, _max_lock_time) = fc::get_lock_time_range(&fountain);
            let stake_amount: u64 = 1_234_567_890;
            let lp_token = spot_dex::new_for_testing<TEST_COIN_A, TEST_COIN_B>(pool_id(), stake_amount, ts::ctx(scenario));
            let lock_time = min_lock_time - 1;
            fp::stake(&clock, &mut fountain, lp_token, lock_time, ts::ctx(scenario));
            ts::return_shared(clock);
            ts::return_shared(fountain);
        };

        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = math::EInvalidLockTime)]
    fun test_exceed_max_lock_time() {
        let flow_amount: u64 = 27_663_000_000_000;
        let flow_interval: u64 = 86400_000 * 7; // 1 week
        let min_lock_time: u64 = flow_interval * 5;
        let max_lock_time: u64 = flow_interval * 20;
        let scenario_val = ftu::setup<TEST_COIN_A, TEST_COIN_B, SUI>(
            flow_amount,
            flow_interval,
            min_lock_time,
            max_lock_time,
            false,
        );
        let scenario = &mut scenario_val;

        ts::next_tx(scenario, @0xcafe);
        {
            let clock = ts::take_shared<Clock>(scenario);
            let fountain = ts::take_shared<Fountain<TEST_COIN_A, TEST_COIN_B, SUI>>(scenario);
            let (_min_lock_time, max_lock_time) = fc::get_lock_time_range(&fountain);
            let stake_amount: u64 = 9_876_543_210;
            let lp_token = spot_dex::new_for_testing<TEST_COIN_A, TEST_COIN_B>(pool_id(), stake_amount, ts::ctx(scenario));
            let lock_time = max_lock_time + 1;
            fp::stake(&clock, &mut fountain, lp_token, lock_time, ts::ctx(scenario));
            ts::return_shared(clock);
            ts::return_shared(fountain);
        };

        ts::end(scenario_val);
    }
}