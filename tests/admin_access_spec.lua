local test=StorageTest.test
local function fixture()
    local c={native=false,started=true,allowed=false,calls=0}
    c.check=OSSecurity.AdminAccess.new({permission='ossecurity.admin',resource='os_devtools',
        ace=function() return c.native end,state=function(resource) assert(resource=='os_devtools');return c.started and 'started' or 'stopped' end,
        delegate=function(resource,source,permission)
            assert(resource=='os_devtools' and source==9 and permission=='ossecurity.admin');c.calls=c.calls+1
            if c.error then error('Unavailable export') end
            return c.allowed
        end})
    return c
end
test('OSCAR adapter preserves explicit ACE true/1 with the authorization resource absent',function()
    local c=fixture();c.started=false
    for _,native in ipairs({true,1}) do c.native=native;assert(c.check(9,'ossecurity.admin')) end
    assert(c.calls==0)
end)
test('OSCAR delegated admin access is checked live and disappears on revocation or provider stop',function()
    local c=fixture();assert(not c.check(9,'ossecurity.admin'));c.allowed=true;assert(c.check(9,'ossecurity.admin'))
    c.allowed=false;assert(not c.check(9,'ossecurity.admin'));c.allowed=true;c.started=false;assert(not c.check(9,'ossecurity.admin'))
    assert(c.calls==3)
end)
test('OSCAR delegation never supplies employee/client tablet ACE roles',function()
    local c=fixture();c.allowed=true
    for _,permission in ipairs({'ossecurity.g6.client','ossecurity.g6.operations','ossecurity.g6.technician','ossecurity.g6.supervisor'}) do assert(not c.check(9,permission)) end
    assert(c.calls==0)
end)
test('OSCAR export errors and non-boolean results fail closed',function()
    local c=fixture();c.error=true;assert(not c.check(9,'ossecurity.admin'));c.error=false
    for _,value in ipairs({1,0,'true'}) do c.allowed=value;assert(not c.check(9,'ossecurity.admin')) end
end)
test('OSCAR integration can be disabled without adding a resource dependency',function()
    local check=OSSecurity.AdminAccess.new({permission='ossecurity.admin',resource=false,ace=function() return false end,
        state=function() error('Must not run') end,delegate=function() error('Must not run') end})
    assert(not check(9,'ossecurity.admin'))
end)
