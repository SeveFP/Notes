local serpent = require("serpent")
local uuid = require("util.uuid");
local notes = require("notes_manager")
local stanza = require("util.stanza")
local dataforms = require("util.dataforms")

local instructions = [[Current features:
·"Healthy Food" Banana → Will create the note «Banana» in the «Healthy Food» topic.
·Show all → Will show all notes from every topic.
·Show → Will show all notes from the default topic.
·Show Healty Food → Will show all notes from the «Healthy Food» topic.
·Set default Healthy Food → Will set the topic «Healty Food» as the default topic.
·Roast Beef and Salad → Will create the note «Roast Beef and Salad» in the default topic.
·Share Healthy Food friend@server.com → Will share the topic «Healthy Food» with friend@server.com
·Instructions or help → Will show this information.]]

notes = notes()
notes:load()
notes:set_auto_persist(true)


function handle_deletion_form(message)
   local submit = message.stanza:get_child("x", "jabber:x:data")
    if submit then
        if submit.attr.type:lower() == "submit" then
            local field = submit:get_child("field")
            if field.attr.var == "deletion-list" then
                notes:set_auto_persist(false)
                for childnode in field:children() do
                    if childnode then
                        if type(childnode) == "table" then
                            notes:delete_note(childnode:get_text())
                        end
                    end
                end
                notes:persist()
                notes:set_auto_persist(true)
            end
        end
    end 
end

function riddim.plugins.notes(bot)
        local function handler(message)
            -- Check if the incoming message is a dataform type=submit 
            -- and check the notes the user wants to delete.
            handle_deletion_form(message)

            if message.body and message.sender then
                local sender = message.sender.jid:match("^(.-)/")
                local command = message.body:gsub(" ", ""):lower()
                local notes_reply = ""

                if command == "showall" or command == "all" then
                    local user_notes = notes:get_all_notes_by_user(sender)
                    if user_notes then
                        for k, note in pairs(user_notes) do
                            note_topics = ""
                            --If it has no topics, it is saved in the default topic
                            --If it has more than one topic, present them as: Topic1, topic2: content
                            for i,topic_id in pairs(note.topics) do
                                local topic = notes:get_topic_by_id(sender, topic_id)
                                note_topics = note_topics .. topic.name .. ", "
                            end
                            note_topics = note_topics:sub(1,note_topics:len()-2) .. "|"
                            notes_reply = notes_reply .. note_topics .. "\t" .. note.content .. "\n" 
                        end 
                    end
                    
                    if notes_reply == "" then
                        notes_reply = "There are no notes yet. Create some now or type «instructions» or «help»"
                    end
                    message:reply(notes_reply)
                
                --default topic
                elseif command == "show" then 
                    local default_topic_notes = notes:get_default_topic_notes_by_user(sender)
                    local default_topic_name = notes:get_user_default_topic(sender).name
                    if default_topic_notes then
                        for k, note in pairs(default_topic_notes) do
                            notes_reply = notes_reply .. default_topic_name .. "|\t" .. note.content .. "\n"
                        end
                    end
                    
                    if notes_reply == "" then
                            notes_reply = "There are no notes yet. Create some now or type «instructions» or «help»"
                    end

                    message:reply(notes_reply)

                elseif command:match("show") then
                    local possible_topic = message.body:match("^%s*(.-)%s*$"):sub(6)
                    local has_topic = notes:topic_exists(sender, possible_topic)
                    if has_topic then
                        local topic = notes:get_topic_by_name(sender, possible_topic).name
                        local topic_notes = notes:get_topic_notes_by_user(sender, possible_topic)
                        for k, note in pairs(topic_notes) do
                            notes_reply = notes_reply .. topic .. "|\t" .. note.content .. "\n"
                        end
                        message:reply(notes_reply)
                    end
                    
                
                elseif command:match("setdefault") then
                    local possible_topic = message.body:match("^%s*(.-)%s*$"):sub(13)
                    if notes:topic_exists(sender, possible_topic) then
                        notes:set_default_user_topic(sender, notes:get_topic_by_name(sender,possible_topic).id)
                    end
                
                elseif command == ("instructions") or command == ("help") then
                        message:reply(instructions)
                
                -- Delete all
                elseif command == "delete" then

                        local user_notes = notes:get_all_notes_by_user(sender)
                        local options = {}
                
                        for k, note in pairs(user_notes) do
                            note_topics = ""
                            for i,topic_id in pairs(note.topics) do
                                local topic = notes:get_topic_by_id(sender, topic_id)
                                note_topics = note_topics .. topic.name .. ", "
                            end
                            note_topics = note_topics:sub(1,note_topics:len()-2) .. "|"
                            options[#options + 1] = {label = note_topics .. "\t" .. note.content, value = note.id} 
                        end
                
                        local layout = {
                            title = "DELETION MENU", instructions = "Select the notes to delete",
                            {name = "deletion-list", type = "list-multi", label = "Select notes", required = false,
                                value = options;
                            };

                        }
                        local form = dataforms.new(layout):form()
                        local reply = stanza.message({ to = sender}):add_child(form)
                        bot:send(reply)
                        
                elseif command:match("delete") then
                    -- TODO match topic's name and send the notes
                elseif command == "topics" then
                    -- TODO Return all created topics
                elseif command:match("share") then
                        local input = message.body:match("^%s*(.-)%s*$")
                        local share_with_jid = input:match("^.* (.-)$")
                        local topic_to_share = input:sub(7):match("^(.-) +" .. share_with_jid)
                        notes:share_topic_with(sender, share_with_jid, topic_to_share)
                
                -- The user wants to create a note
                else
                    local user_topics_id = {}
                    local content = message.body:match([[^.*"(.-)$]])
                    
                    for topic_name in message.body:gmatch([["(.-)"]]) do
                        local topic = notes:create_and_add_topic(sender, topic_name)
                        user_topics_id[#user_topics_id + 1] = topic.id
                    end
                    
                    if #user_topics_id < 1 then
                        local topic = notes:get_user_default_topic(sender)
                        user_topics_id = {topic.id}
                        content = message.body
                    end
                    notes:add_note(sender, content, user_topics_id)
                end
            end
            end
        bot:hook("message", handler);
        bot:hook("groupchat/joined", function(room)
                room:hook("message", handler)
        end);
end