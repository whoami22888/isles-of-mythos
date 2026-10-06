import {describe,expect,it} from 'vitest';
import {parseClientMessage} from './protocol.js';

describe('Gate 10 guild protocol',()=>{
  it('parses guild management and bank actions',()=>{
    expect(parseClientMessage(JSON.stringify({type:'create_guild',requestId:'g',name:'Sea Wardens',tag:'WARD'}))?.type).toBe('create_guild');
    expect(parseClientMessage(JSON.stringify({type:'list_guild_invitations',requestId:'i'}))?.type).toBe('list_guild_invitations');
    expect(parseClientMessage(JSON.stringify({type:'guild_bank_deposit',requestId:'d',guildId:'1',itemId:'wood',quantity:10,gold:'25'}))?.type).toBe('guild_bank_deposit');
    expect(parseClientMessage(JSON.stringify({type:'set_guild_permission',requestId:'p',guildId:'1',rank:'veteran',permission:'bank_withdraw',enabled:true}))?.type).toBe('set_guild_permission');
  });
});
