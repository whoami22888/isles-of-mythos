          }catch(error){
            const code=errorCode(error, "CAPTURE_FAILED");
            if (code === "NO_CAPTURE_ORB") { send(socket, { type: "error", code: "NO_CAPTURE_ORB" }); return; }
            if (code === "CREATURE_ALREADY_CAPTURED") { send(socket, { type: "error", code: "CREATURE_ALREADY_CAPTURED" }); return; }
            throw error;
          }
        }

        if (message.type === "tame") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          try{const result=await creatures.tame(userId,message.creatureId);
            const player=players.get(userId);
            if(result.consumed&&player) { player.inventory["creature.feed"]=Math.max(0,Number(player.inventory["creature.feed"]??0)-1); players.markDirty(userId); }
            send(socket,{type:"creature_state",requestId:message.requestId,creature:result.creature});}
          catch(error){
            const code=errorCode(error, "TAME_FAILED");
            if (code === "CREATURE_NOT_FOUND") { send(socket, { type: "error", code: "CREATURE_NOT_FOUND" }); return; }
            if (code === "NO_CREATURE_FEED") { send(socket, { type: "error", code: "NO_CREATURE_FEED" }); return; }
            throw error;
          }
          return;
        }

        if (message.type === "set_creature_party") {
          if(!userId){send(socket,{type:"error",code:"AUTH_REQUIRED"});return;}
          try{