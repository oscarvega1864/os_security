-- Frontera con las natives: el BOOL puede llegar a Lua como true/false o 1/0.
-- El almacen conserva un contrato booleano estricto y verifica siempre los bytes.
OSSecurity.ResourceFiles = {}

function OSSecurity.ResourceFiles.new(options)
    local files = {}
    local function permissionError(err)
        return type(err) == 'string' and (err:lower():find('permission denied', 1, true)
            or err:lower():find('eacces', 1, true)) ~= nil
    end

    function files.read(path)
        local ok, content = pcall(options.load, options.resource, path)
        if not ok then
            return nil, 'Excepcion en LoadResourceFile.', {
                stage = permissionError(content) and 'permission' or 'read', operation = 'load'
            }
        end
        if content ~= nil then return content end
        -- Diagnostico de ausencia/acceso en modo lectura; nunca truncar para probar.
        local opened, file, _, code = pcall(options.open, ('@%s/%s'):format(options.resource, path), 'rb')
        if not opened then
            return nil, 'No se pudo comprobar la ausencia del archivo.', {
                stage = permissionError(file) and 'permission' or 'read', operation = 'probe'
            }
        end
        if file then
            file:close()
            return nil, 'El archivo existe pero LoadResourceFile no pudo leerlo.', { stage = 'read', operation = 'load' }
        end
        if code == 2 then return nil end -- ENOENT: primera ejecucion sin datos.
        return nil, 'No se pudo comprobar la ausencia del archivo.', {
            stage = code == 13 and 'permission' or 'read', operation = 'probe', errno = code
        }
    end

    function files.write(path, content)
        local ok, result = pcall(options.save, options.resource, path, content, #content)
        local details = { stage = 'write', nativeType = type(result) }
        if ok then details.nativeResult = result end
        if not ok then
            details.stage = permissionError(result) and 'permission' or 'write'
            details.exception = true -- No propagar el texto potencialmente sensible.
        end
        return ok and (result == true or result == 1), details
    end

    return files
end
