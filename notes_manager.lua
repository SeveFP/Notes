local serpent = require("serpent")
local uuid = require("util.uuid");

local Notes = {}
Notes.__index = Notes

setmetatable(Notes, {__call = function(cls, ...) return cls.new(...) end})

function Notes.new(file_path)
    -- Every data structure in this class should be a hash table instead of simple arrays.
    -- If data gets bigger, using arrays will not be an efficient way of storing and retrieving the data.
    local self = setmetatable({}, Notes)
    self.data = { 
        users = {},
        notes = {},
        topics = {}
    }
    self.file_path = file_path or "notes_db.lua"
    self.auto_persist = false
    return self
end


function Notes:add_user(jid)
    local toReturn = false
    if not self:user_exists(jid) then
        local user = {jid = jid, default_topic = self:get_user_default_topic(jid).id ,creation_date = os.time()}
        self.data.users[#self.data.users +1] = user
        toReturn = true
        if self.auto_persist then
            self:persist()
        end
    end
    return toReturn
end

function Notes:user_exists(jid)
   local found = false
   local i = 1
    while i <= #self.data.users and not found do
        if self.data.users[i].jid == jid then
            found = true
        end
        i = i + 1
    end
    return found
end


function Notes:set_default_user_topic(jid, new_default_topic_id)
  local found = false
  local i = 1
   while i <= #self.data.users and not found do
      if self.data.users[i].jid == jid then
          self.data.users[i].default_topic = new_default_topic_id
          found = true
            if self.auto_persist then
                self:persist()
            end
      end
      i = i +1
   end
end

function Notes:add_note(jid, content, topics)
   --Check if user exists with Notes:user_exists()
   --If not, create it.
   --Check if topics is string or table
   --If string, insert the topic inside the topics table
   --If table, insert elements in table
   
    if not self:user_exists(jid) then
        self:add_user(jid)
    end
        
    local note = {
        id = uuid.generate(),
        author = jid,
        content = content,
        creation_date = os.time(),
        topics = {},
        shared_with = {jid},
    }
    
    if type(topics) == "string" then
        note.topics = {topics}
    elseif type(topics) == "table" then
        note.topics = topics
    end
    
    self.data.notes[#self.data.notes +1] = note
    
    if self.auto_persist then
        self:persist()
    end
end

function Notes:delete_note(id)
    local i = 1
    local found = false
    while i <= #self.data.notes and not found do
        if self.data.notes[i].id == id then
            found = true
            for i = i, #self.data.notes-1 do
               self.data.notes[i] = self.data.notes[i+1] 
            end
        end
        i = i +1
    end
    if found then
        self.data.notes[#self.data.notes] = nil
        if self.auto_persist then
            self:persist()
        end
    end
    return found
end

function Notes:get_all_notes_by_user(jid)
    local toReturn = {}
    for k, note in pairs(self.data.notes) do
        local found = false
        local i = 1
        while i <= #note.topics and not found do
           local topic = self:get_topic_by_id(jid,note.topics[i])
           if topic then
                if self:topic_exists(jid, topic.name) then
                    found = true
                    toReturn[#toReturn +1] = note
                end 
           end
            i = i+1
        end
    end
    return next(toReturn) and toReturn or nil
end

function Notes:get_default_topic_notes_by_user(jid)
    local toReturn = {}
    if self:user_exists(jid) then
        local default_topic = self:get_user_default_topic(jid)
        for k, note in pairs(self.data.notes) do
            for x, jid_shared in pairs(note.shared_with) do
                if jid_shared == jid then
                    for _,id in pairs(note.topics) do
                        if id == default_topic.id then
                            toReturn[#toReturn + 1] = note
                        end
                    end
                end
            end
        end
    end
    return next(toReturn) and toReturn or nil
end

function Notes:get_user_default_topic(jid)
    local toReturn = {}
    local i = 1
    local found = false
    
    -- This should be in a function called Notes:get_user_by_jid()
    local user = {}
    while i <= #self.data.users and not found do
       if self.data.users[i].jid == jid then
           user = self.data.users[i]
           found = true
       end
       i = i +1
    end
    --Reset for the next while loop
    i = 1
    found = false

    while i <= #self.data.topics and not found do
        for _, jid_shared in pairs(self.data.topics[i].shared_with) do
            if jid_shared == jid then
                if self.data.topics[i].id == user.default_topic then
                    toReturn = self.data.topics[i]
                    found = true
                end
            end
        end
        i = i +1 
    end

    if not found then
       toReturn = self:create_and_add_topic(jid, "General") 
    end
    
    return toReturn
end

function Notes:get_topic_notes_by_user(jid, topic_name)
   local toReturn = {}
   local topic_id = self:get_topic_by_name(jid, topic_name).id
    for k, note in pairs(self.data.notes) do
        for i, id in pairs(note.topics) do
            if id == topic_id then
                toReturn[#toReturn + 1] = note
            end
        end
    end

    return next(toReturn) and toReturn or nil
end


function Notes:topic_exists(jid, topic_name)
    local found = false
    local i = 1
    while i <= #self.data.topics and not found do
        for _, jid_shared in pairs(self.data.topics[i].shared_with) do
            if jid_shared == jid then
                if self.data.topics[i].name:lower() == topic_name:lower() then
                    found = true 
                end
            end
        end
        i = i +1
    end
    
    return found
end

-- shared_with should be passed as parameter too
function Notes:create_topic(jid, topic_name)
    local topic = {}
    if not self:topic_exists(jid, topic_name) then
        topic = { 
            id = uuid.generate(),
            author = jid,
            name = topic_name,
            creation_date = os.date(),
            topics = {},
            shared_with = {jid}
        }
    else
        topic = self:get_topic_by_name(jid, topic_name)
    end
    
    return topic
end

function Notes:add_topic(topic)
   self.data.topics[#self.data.topics +1] = topic 
    if self.auto_persist then
        self:persist()
    end
end


function Notes:get_topic_by_name(jid, topic_name)
    local toReturn = nil
    local i = 1
    while i <= #self.data.topics and not toReturn do
        for _, jid_shared in pairs(self.data.topics[i].shared_with) do
            if jid_shared == jid then
                if self.data.topics[i].name:lower() == topic_name:lower() then
                    toReturn = self.data.topics[i]
                end
            end
        end
        i = i +1
    end
    
    return toReturn
end

function Notes:get_topic_by_id(jid, topic_id)
    local toReturn = nil
    local i = 1
    while i <= #self.data.topics and not toReturn do
        if self.data.topics[i].id == topic_id then
            for _, jid_shared in pairs(self.data.topics[i].shared_with) do
                if jid_shared == jid then
                    toReturn = self.data.topics[i]
                end
                
            end
        end
        
        i = i +1
    end
    
    return toReturn
end

function Notes:create_and_add_topic(jid, topic_name)
    local topic = {}
    if not self:topic_exists(jid, topic_name) then
        topic = self:create_topic(jid, topic_name)
        self:add_topic(topic)
        --if auto_persist
        if self.auto_persist then
            self:persist()
        end
    else
        topic = self:get_topic_by_name(jid, topic_name)
    end
    print(topic.name, topic.id, "\n")

    return topic
end

-- Missing input validation (length of names, if names is a table, etc)
function Notes:get_topics_by_name(jid, names)
        local toReturn = {}
        for k, topic_name in pairs(names) do
            local topic = {}
            if self:topic_exists(jid, topic_name) then
                topic = self:get_topic_by_name(jid, topic_name)
            else
                topic = self:create_topic(jid, topic_name)
                self:add_topic(topic)
            end
            toReturn[#toReturn +1] = topic
        end
            
    
end

-- Missing input validation (length of names, if names is a table, etc)
function Notes:get_topics_id_by_name(jid, name)
    local toReturn = {}    
    for k,topic_name in pairs(name) do
        local topic = self:get_topic_by_name(topic_name)
        if topic then
            toReturn[#toReturn +1] = topic.id
        end
    end
    
    return next(toReturn) and toReturn or nil
end

--The user doesn't need to be a registered user in the service, the jid will be added automatically.
function Notes:share_topic_with(author, jid, topic_name)
    local topic = self:get_topic_by_name(author, topic_name)
    if topic then
        if topic.author == author then
            topic.shared_with[#topic.shared_with +1] = jid 
            if self.auto_persist then
                self:persist()
            end
        end
    end
end

function Notes:unshare_topic_with(author, jid, topic_name)
    local topic = self:get_topic_by_name(topic_name)
    if topic then
        if topic.author == author then
            local i = 1
            local found = false
            while i <= #topic.shared_with and not found do
               if topic.shared_with[i] == jid then
                   for k = i, #topic.shared_with-1 do
                       topic.shared_with[k] = topic.shared_with[k +1]
                   end
                   topic.shared_with[#topic.shared_with] = nil
                   found = true
                    if self.auto_persist then
                        self:persist()
                    end
               end
               i = i +1
            end
        end
    end 
end


function Notes:set_file_path(path)
   local toReturn = false
    
    if path then
        self.file_path = path
        toReturn = true
    end
    
    return toReturn
end

function Notes:persist()
  local file = io.open(self.file_path, "w")
  file:write(serpent.block(self.data))
  file:close()
end

function Notes:load()
   local toReturn = false
   local file = io.open(self.file_path, "r")
    if file then
        local ok, data = serpent.load(file:read("*a"), {safe = false})
        file:close()
        
        if ok and data then 
            self.data = data
            toReturn = true
        end
    end
  
    return toReturn
end

function Notes:set_auto_persist(boolean)
   if type(boolean) == "boolean" then
       self.auto_persist = boolean
   end
    
end
return Notes