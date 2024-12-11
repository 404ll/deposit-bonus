#[test_only ,allow(unused_use)] 
module deposit_bonus::deposit_bonus_tests;

use sui::clock::Clock;
use sui::random::Random;
use sui::balance::{Self,Balance};
use sui::coin::{Self,Coin};
use sui_system::sui_system::{Self,SuiSystemState};
use sui::test_utils::assert_eq;
use sui::test_scenario::{Self as tests, Scenario};
use sui::test_utils;
use sui_system::governance_test_utils::{add_validator_full_flow, advance_epoch, remove_validator, set_up_sui_system_state, create_sui_system_state_for_testing, stake_with, unstake};
use deposit_bonus::utils::log;
use deposit_bonus::deposit_bonus::{Self as db,Storage,UserInfo,UserShare,query_user_info,
                                    AdminCap,OperatorCap,assign_operator,deposit,get_share_amount,
                                    create_random_point,};

const VALIDATOR1_ADDR : address = @0x1;
const VALIDATOR2_ADDR : address = @0x2;
const ADMIN_ADDR : address = @0xa;
const OPERATOR_ADDR : address = @0xb;
const USER1_ADDR : address = @0x11;
const USER2_ADDR : address = @0x12;
#[test_only] 
fun test_init() : (Clock,Random,Scenario,Storage)
{
    let mut sc = tests::begin(@0x0);
    sui::random::create_for_testing(sc.ctx());
    let clock = sui::clock::create_for_testing(sc.ctx());
   

    tests::next_tx(&mut sc,ADMIN_ADDR);
    let random = sc.take_shared<Random>();
    {
        deposit_bonus::deposit_bonus::init_for_testing(sc.ctx());
    };
    tests::next_tx(&mut sc,@0xa);
    
    let admin_cap = tests::take_from_address<AdminCap>(&sc, ADMIN_ADDR);
    let operator_cap = tests::take_from_address<OperatorCap>(&sc, ADMIN_ADDR);
    assign_operator(&admin_cap,operator_cap, OPERATOR_ADDR);
    tests::return_to_address(ADMIN_ADDR,admin_cap);

    set_up_sui_system_state(vector[@0x1, @0x2]);
    {
        sc.next_tx(@0x0);
        let mut system_state = sc.take_shared<SuiSystemState>();
        system_state.active_validator_by_address(@0x1);
        tests::return_shared(system_state);
       
        // .get_staking_pool_ref();
        // assert!(staking_pool.pending_stake_amount() == 0, 0);
        // assert!(staking_pool.pending_stake_withdraw_amount() == 0, 0);
        // assert!(staking_pool.sui_balance() == 100 * 1_000_000_000, 0);
        // tests::return_shared(system_state);
    };

    sc.next_tx(@0x0);
    let storage = tests::take_shared<Storage>(&sc);
    (clock,random,sc,storage)

}

#[test_only]
fun test_finish(clock : Clock,
            random: Random,
            sc :Scenario,
            storage:Storage){
    tests::return_shared(random);
    tests::return_shared(storage);
    test_utils::destroy(clock);
    tests::end(sc);
}



#[test]
fun test_deposit(){
    let  (clock,random,mut sc,mut storage) = test_init();
    let mut system_state = sc.take_shared<SuiSystemState>();
    let amount = 50_000_000_000;
    let amount2 = 5_000_000_000;
    tests::next_tx(&mut sc, USER1_ADDR);
    {
    
        let coin = coin::mint_for_testing(amount, sc.ctx());
        deposit(&clock, &mut storage, &mut system_state,
                VALIDATOR1_ADDR, coin, sc.ctx());

        let share = db::get_share_amount(&storage, USER1_ADDR);
        assert_eq(share, amount);
        assert_eq(storage.total_staked_amount() ,amount);
        assert_eq(storage.total_share_amount(),amount);
        let user_info = query_user_info(&storage,sc.ctx());
        assert_eq(user_info.user_id() , USER1_ADDR);
        assert_eq(user_info.user_orignal_amount(), amount);
        assert_eq(user_info.user_reward(), 0);
        tests::next_tx(&mut sc,USER1_ADDR);
        
        let share_amount = db::get_share_amount(&storage, USER1_ADDR);
        assert_eq(share_amount , amount );
    };


    tests::next_tx(&mut sc, USER2_ADDR);
    {
        let coin = coin::mint_for_testing(amount2, sc.ctx());
        deposit(&clock, &mut storage, &mut system_state,
                VALIDATOR1_ADDR, coin, sc.ctx());

        let share = db::get_share_amount(&storage, USER2_ADDR);
        assert_eq(share, amount2);
        assert_eq(storage.total_staked_amount() ,amount + amount2);
        let user_info = query_user_info(&storage,sc.ctx());
        assert_eq(user_info.user_id() , USER2_ADDR);
        assert_eq(user_info.user_orignal_amount(), amount2);
        assert_eq(user_info.user_reward(), 0);
        
        let share = db::get_share_amount(&storage, USER2_ADDR);
        assert_eq(share , amount2 );
    };
    

    tests::next_tx(&mut sc, USER1_ADDR);
    {
        let withdraw_amount = 3_000_000_000;
        db::entry_withdraw(&clock, &mut storage, &mut system_state,
                             withdraw_amount, sc.ctx());

       
        let share = db::get_share_amount(&storage, USER1_ADDR);
        assert_eq(share, amount - withdraw_amount);

        assert_eq(storage.total_staked_amount() ,amount + amount2 - withdraw_amount);

        let user_info = db::query_user_by_addr(&storage, USER2_ADDR);
        assert_eq(user_info.user_id() , USER2_ADDR);
        assert_eq(user_info.user_orignal_amount(), amount2);
        assert_eq(user_info.user_reward(), 0);

        let user_info = query_user_info(&storage,sc.ctx());
        assert_eq(user_info.user_id() , USER1_ADDR);
        assert_eq(user_info.user_orignal_amount(), amount - withdraw_amount);
        assert_eq(user_info.user_reward(), 0);

        let share = db::get_share_amount(&storage, USER2_ADDR);
        assert_eq(share , amount2 );
    };

    let hit_users = db::get_hit_users(&mut storage, &random, sc.ctx());
    log(b"--------------hit users------------------\n",&db::convert_to_vector(&hit_users));
    log(b"seed",&storage.get_seed());
    sui::linked_table::drop(hit_users);
    

    let hit_users = db::get_hit_users(&mut storage, &random, sc.ctx());
    log(b"--------------hit users------------------\n",&db::convert_to_vector(&hit_users));
    log(b"seed",&storage.get_seed());
    sui::linked_table::drop(hit_users);
    tests::return_shared(system_state);
 
    test_finish(clock, random,sc,storage);

}

use deposit_bonus::range;
#[test]
fun test_hit_range(){
    let  (clock,random,mut sc,mut storage) = test_init();
    tests::next_tx(&mut sc, @0xc);
    let mut i = 0;
    while(i < 5)
    {
        let ranges = db::get_hit_range(&mut storage, &random, sc.ctx());
        i = i + 1;
        log(b"ranges ",&range::encode_ranges(&ranges).to_ascii_string());
    };
    test_finish(clock, random,sc,storage);

}


#[test]
fun test_point(){
    let  (clock,random,mut sc,mut storage) = test_init();
    tests::next_tx(&mut sc, @0xc);
    let mut i = 0;
    while(i < 10){
        let val = db::create_random_point(&mut storage,&random,sc.ctx());
        std::debug::print(&val);
        i = i + 1;
    };

    test_finish(clock, random,  sc,storage);
}