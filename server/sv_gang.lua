local QRCore = exports['qr-core']:GetCoreObject()
local GangAccounts = {}

function GetGangAccount(account)
	return GangAccounts[account] or 0
end

function AddGangMoney(account, amount)
	if not GangAccounts[account] then
		GangAccounts[account] = 0
	end

	GangAccounts[account] = GangAccounts[account] + amount
	MySQL.insert('INSERT INTO management_funds (job_name, amount, type) VALUES (:job_name, :amount, :type) ON DUPLICATE KEY UPDATE amount = :amount',
		{
			['job_name'] = account,
			['amount'] = GangAccounts[account],
			['type'] = 'gang'
		})
end

function RemoveGangMoney(account, amount)
	local isRemoved = false
	if amount > 0 then
		if not GangAccounts[account] then
			GangAccounts[account] = 0
		end

		if GangAccounts[account] >= amount then
			GangAccounts[account] = GangAccounts[account] - amount
			isRemoved = true
		end

		MySQL.update('UPDATE management_funds SET amount = ? WHERE job_name = ? and type = "gang"', { GangAccounts[account], account })
	end
	return isRemoved
end

MySQL.ready(function ()
	local gangmenu = MySQL.query.await('SELECT job_name,amount FROM management_funds WHERE type = "gang"', {})
	if not gangmenu then return end

	for _,v in ipairs(gangmenu) do
		GangAccounts[v.job_name] = v.amount
	end
end)

RegisterNetEvent("qr-gangmenu:server:withdrawMoney", function(amount)
	local src = source
	local Player = QRCore.Functions.GetPlayer(src)

	if not Player.PlayerData.gang.isboss then ExploitBan(src, 'withdrawMoney Exploiting') return end

	local gang = Player.PlayerData.gang.name
	if RemoveGangMoney(gang, amount) then
		Player.Functions.AddMoney("cash", amount, 'Gang menu withdraw')
		TriggerEvent('qr-log:server:CreateLog', 'gangmenu', 'Withdraw Money', 'yellow', Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. ' successfully withdrew $' .. amount .. ' (' .. gang .. ')', false)
		TriggerClientEvent('QRCore:Notify', src, "You have withdrawn: $" ..amount, "success")
	else
		TriggerClientEvent('QRCore:Notify', src, "You dont have enough money in the account!", "error")
	end

	TriggerClientEvent('qr-gangmenu:client:OpenMenu', src)
end)

RegisterNetEvent("qr-gangmenu:server:depositMoney", function(amount)
	local src = source
	local Player = QRCore.Functions.GetPlayer(src)

	if not Player.PlayerData.gang.isboss then ExploitBan(src, 'depositMoney Exploiting') return end

	if Player.Functions.RemoveMoney("cash", amount) then
		local gang = Player.PlayerData.gang.name
		AddGangMoney(gang, amount)
		TriggerEvent('qr-log:server:CreateLog', 'gangmenu', 'Deposit Money', 'yellow', Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. ' successfully deposited $' .. amount .. ' (' .. gang .. ')', false)
		TriggerClientEvent('QRCore:Notify', src, "You have deposited: $" ..amount, "success")
	else
		TriggerClientEvent('QRCore:Notify', src, "You dont have enough money to add!", "error")
	end

	TriggerClientEvent('qr-gangmenu:client:OpenMenu', src)
end)

QRCore.Functions.CreateCallback('qr-gangmenu:server:GetAccount', function(_, cb, GangName)
	local gangmoney = GetGangAccount(GangName)
	cb(gangmoney)
end)

-- Get Employees
QRCore.Functions.CreateCallback('qr-gangmenu:server:GetEmployees', function(source, cb, gangname)
	local src = source
	local Player = QRCore.Functions.GetPlayer(src)

	if not Player.PlayerData.gang.isboss then ExploitBan(src, 'GetEmployees Exploiting') return end

	local employees = {}
	local players = MySQL.query.await("SELECT * FROM `players` WHERE `gang` LIKE '%".. gangname .."%'", {})
	if players[1] ~= nil then
		for _, value in pairs(players) do
			local isOnline = QRCore.Functions.GetPlayerByCitizenId(value.citizenid)

			if isOnline then
				employees[#employees+1] = {
				empSource = isOnline.PlayerData.citizenid,
				grade = isOnline.PlayerData.gang.grade,
				isboss = isOnline.PlayerData.gang.isboss,
				name = '🟢' .. isOnline.PlayerData.charinfo.firstname .. ' ' .. isOnline.PlayerData.charinfo.lastname
				}
			else
				employees[#employees+1] = {
				empSource = value.citizenid,
				grade =  json.decode(value.gang).grade,
				isboss = json.decode(value.gang).isboss,
				name = '❌' ..  json.decode(value.charinfo).firstname .. ' ' .. json.decode(value.charinfo).lastname
				}
			end
		end
	end
	cb(employees)
end)

-- Grade Change
RegisterNetEvent('qr-gangmenu:server:GradeUpdate', function(data)
	local src = source
	local Player = QRCore.Functions.GetPlayer(src)
	local Employee = QRCore.Functions.GetPlayerByCitizenId(data.cid)

	if not Player.PlayerData.gang.isboss then ExploitBan(src, 'GradeUpdate Exploiting') return end
	if data.grade > Player.PlayerData.gang.grade.level then TriggerClientEvent('QRCore:Notify', src, "You cannot promote to this rank!", "error") return end

	if Employee then
		if Employee.Functions.SetGang(Player.PlayerData.gang.name, data.grade) then
			TriggerClientEvent('QRCore:Notify', src, "Successfully promoted!", "success")
			TriggerClientEvent('QRCore:Notify', Employee.PlayerData.source, "You have been promoted to " ..data.gradename..".", "success")
		else
			TriggerClientEvent('QRCore:Notify', src, "Grade does not exist.", "error")
		end
	else
		TriggerClientEvent('QRCore:Notify', src, "Civilian is not in city.", "error")
	end
	TriggerClientEvent('qr-gangmenu:client:OpenMenu', src)
end)

-- Fire Member
RegisterNetEvent('qr-gangmenu:server:FireMember', function(target)
	local src = source
	local Player = QRCore.Functions.GetPlayer(src)
	local Employee = QRCore.Functions.GetPlayerByCitizenId(target)

	if not Player.PlayerData.gang.isboss then ExploitBan(src, 'FireEmployee Exploiting') return end

	if Employee then
		if target ~= Player.PlayerData.citizenid then
			if Employee.PlayerData.gang.grade.level > Player.PlayerData.gang.grade.level then TriggerClientEvent('QRCore:Notify', src, "You cannot fire this citizen!", "error") return end
			if Employee.Functions.SetGang("none", '0') then
				TriggerEvent("qr-log:server:CreateLog", "gangmenu", "Gang Fire", "orange", Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname .. ' successfully fired ' .. Employee.PlayerData.charinfo.firstname .. " " .. Employee.PlayerData.charinfo.lastname .. " (" .. Player.PlayerData.gang.name .. ")", false)
				TriggerClientEvent('QRCore:Notify', src, "Gang Member fired!", "success")
				TriggerClientEvent('QRCore:Notify', Employee.PlayerData.source , "You have been expelled from the gang!", "error")
			else
				TriggerClientEvent('QRCore:Notify', src, "Error.", "error")
			end
		else
			TriggerClientEvent('QRCore:Notify', src, "You can\'t kick yourself out of the gang!", "error")
		end
	else
		local player = MySQL.query.await('SELECT * FROM players WHERE citizenid = ? LIMIT 1', {target})
		if player[1] ~= nil then
			Employee = player[1]
			Employee.gang = json.decode(Employee.gang)
			if Employee.gang.grade.level > Player.PlayerData.job.grade.level then TriggerClientEvent('QRCore:Notify', src, "You cannot fire this citizen!", "error") return end
			local gang = {}
			gang.name = "none"
			gang.label = "No Affiliation"
			gang.payment = 0
			gang.onduty = true
			gang.isboss = false
			gang.grade = {}
			gang.grade.name = nil
			gang.grade.level = 0
			MySQL.update('UPDATE players SET gang = ? WHERE citizenid = ?', {json.encode(gang), target})
			TriggerClientEvent('QRCore:Notify', src, "Gang member fired!", "success")
			TriggerEvent("qr-log:server:CreateLog", "gangmenu", "Gang Fire", "orange", Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname .. ' successfully fired ' .. Employee.PlayerData.charinfo.firstname .. " " .. Employee.PlayerData.charinfo.lastname .. " (" .. Player.PlayerData.gang.name .. ")", false)
		else
			TriggerClientEvent('QRCore:Notify', src, "Civilian is not in city.", "error")
		end
	end
	TriggerClientEvent('qr-gangmenu:client:OpenMenu', src)
end)

-- Recruit Player
RegisterNetEvent('qr-gangmenu:server:HireMember', function(recruit)
	local src = source
	local Player = QRCore.Functions.GetPlayer(src)
	local Target = QRCore.Functions.GetPlayer(recruit)

	if not Player.PlayerData.gang.isboss then ExploitBan(src, 'HireEmployee Exploiting') return end

	if Target and Target.Functions.SetGang(Player.PlayerData.gang.name, 0) then
		TriggerClientEvent('QRCore:Notify', src, "You hired " .. (Target.PlayerData.charinfo.firstname .. ' ' .. Target.PlayerData.charinfo.lastname) .. " come " .. Player.PlayerData.gang.label .. "", "success")
		TriggerClientEvent('QRCore:Notify', Target.PlayerData.source , "You have been hired as " .. Player.PlayerData.gang.label .. "", "success")
		TriggerEvent('qr-log:server:CreateLog', 'gangmenu', 'Recruit', 'yellow', (Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname).. ' successfully recruited ' .. Target.PlayerData.charinfo.firstname .. ' ' .. Target.PlayerData.charinfo.lastname .. ' (' .. Player.PlayerData.gang.name .. ')', false)
	end
	TriggerClientEvent('qr-gangmenu:client:OpenMenu', src)
end)

-- Get closest player sv
QRCore.Functions.CreateCallback('qr-gangmenu:getplayers', function(source, cb)
	local src = source
	local players = {}
	local PlayerPed = GetPlayerPed(src)
	local pCoords = GetEntityCoords(PlayerPed)
	for _, v in pairs(QRCore.Functions.GetPlayers()) do
		local targetped = GetPlayerPed(v)
		local tCoords = GetEntityCoords(targetped)
		local dist = #(pCoords - tCoords)
		if PlayerPed ~= targetped and dist < 10 then
			local ped = QRCore.Functions.GetPlayer(v)
			players[#players+1] = {
			id = v,
			coords = GetEntityCoords(targetped),
			name = ped.PlayerData.charinfo.firstname .. " " .. ped.PlayerData.charinfo.lastname,
			citizenid = ped.PlayerData.citizenid,
			sources = GetPlayerPed(ped.PlayerData.source),
			sourceplayer = ped.PlayerData.source
			}
		end
	end
		table.sort(players, function(a, b)
			return a.name < b.name
		end)
	cb(players)
end)
