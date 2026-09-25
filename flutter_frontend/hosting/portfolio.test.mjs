import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { portfolio, validatePortfolio } from './portfolio.js';
const asset = (kind = 'variable') => ({ id:'a', kind, name:kind === 'fixed' ? 'Tesouro Prefixado 2029' : 'Itaúsa PN', ticker:kind === 'fixed' ? '' : 'ITSA4', institution:'C6 Bank', notes:'', maturity:kind === 'fixed' ? '2029-01-01' : '', rate:null });
const event = (changes = {}) => ({id:'e1',assetId:'a',type:'deposit',date:'2026-01-01',amount:10000,fees:0,quantity:10,price:10,notes:'',...changes});
const data = (events = [event()], kind = 'variable') => ({assets:[asset(kind)],events});
function database() {
  const db = new DatabaseSync(':memory:');
  db.exec(fs.readFileSync(new URL('../drizzle/0001_investment_portfolios.sql', import.meta.url),'utf8'));
  return {DB:{prepare(sql) {return {bind(...args) {const statement=db.prepare(sql);return {first:async()=>statement.get(...args),run:async()=>({meta:{changes:statement.run(...args).changes}})};}};}}};
}
const identity = (id = 1, writable = true) => async () => Response.json({ok:true,user:{id,login:`user${id}`,active:true,permissions:writable?['read','write']:['read']}});
const request = (method='GET',body) => new Request('https://example.test/api/portfolio-v2',{method,headers:{authorization:'Bearer test'},...(body?{body:JSON.stringify(body)}:{})});
test('partial withdrawal, backdated chronology and prices validate',()=>{
  validatePortfolio(data([event({id:'sale',type:'withdraw',date:'2026-02-01',quantity:4,price:12,amount:4800}),event()]));
  assert.throws(()=>validatePortfolio(data([event(),event({id:'sale',type:'withdraw',quantity:11,amount:11000})])),/quantidade/);
  assert.throws(()=>validatePortfolio(data([event({id:'sale',type:'withdraw',date:'2025-12-01'})])),/quantidade/);
});
test('fixed income mark-to-market and withdrawal use dated balance',()=>{
  const entries=[event({quantity:0,price:0}),event({id:'mark',type:'valuation',amount:12000,quantity:0,price:0}),event({id:'sale',type:'withdraw',amount:11000,quantity:0,price:0})];
  validatePortfolio(data(entries,'fixed'));
  assert.throws(()=>validatePortfolio(data([entries[0],entries[2]],'fixed')),/saldo/);
});
test('reject impossible dates, oversize money, inconsistent gross, fees and duplicate ids',()=>{
  for(const e of [event({date:'2026-02-30'}),event({date:'2099-01-01'}),event({amount:10001}),event({amount:NaN}),event({fees:-1}),event({quantity:0}),event({price:Infinity})]) assert.throws(()=>validatePortfolio(data([e])));
  assert.throws(()=>validatePortfolio(data([event(),event()])));
  assert.throws(()=>validatePortfolio(data([event({type:'valuation',fees:1})])));
  assert.throws(()=>validatePortfolio(data([event({type:'income',amount:100,fees:101})])));
});
test('real SQLite persistence and optimistic concurrency prevent lost updates',async()=>{
  const env=database();
  const first=await portfolio(request('PUT',{revision:0,data:data()}),env,identity());
  assert.equal(first.status,200);
  assert.equal((await first.json()).revision,1);
  const stale=await portfolio(request('PUT',{revision:0,data:data([])}),env,identity());
  assert.equal(stale.status,409);
  const read=await portfolio(request(),env,identity());
  assert.equal((await read.json()).data.events.length,1);
  const next=await portfolio(request('PUT',{revision:1,data:data([event(),event({id:'income',type:'income',amount:200,quantity:0,price:0})])}),env,identity());
  assert.equal(next.status,200);
  assert.equal((await next.json()).revision,2);
  assert.equal((await portfolio(request('PUT',{revision:1,data:data([])}),env,identity())).status,409);
});
test('user isolation and viewer permissions are enforced on server',async()=>{
  const env=database();
  await portfolio(request('PUT',{revision:0,data:data()}),env,identity(1));
  const other=await portfolio(request(),env,identity(2));
  assert.equal((await other.json()).data.assets.length,0);
  assert.equal((await portfolio(request('PUT',{revision:0,data:data()}),env,identity(2,false))).status,403);
  assert.equal((await portfolio(new Request('https://example.test'),env,identity())).status,401);
  assert.equal((await portfolio(request(),env,async()=>new Response('',{status:401}))).status,401);
  assert.equal((await portfolio(request(),env,async()=>new Response('',{status:503}))).status,503);
});
