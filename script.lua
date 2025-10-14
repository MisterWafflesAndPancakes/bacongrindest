return function()
	-- Get Services
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local player = Players.LocalPlayer
	
	-- State and helpers
	local activeRole
	local loopConnection
	local winConnection
	local isActive = false
	local restartRole
	local listenForWin
	local runLoop
	local recordCycle
	local getCycleAverage  
	local switchToSolo
	
	-- Handlers (assigned later)
	local handleOnOffClick
	local handleSoloClick
	
	-- Adaptive restart state
	local won = false  -- unified win flag (used for both roles)
	local timeoutElapsed = false
	
	-- Cycle tracking (10‑cycle buffer only)
	local cycleDurations10 = { [1] = {}, [2] = {} }
	local lastCycleTime = { [1] = nil, [2] = nil }
	
	-- Drift‑proof wait helper
	local function waitSeconds(seconds)
		local start = os.clock()
		repeat RunService.Heartbeat:Wait() until os.clock() - start >= seconds
	end
	
	-- RemoteEvent reference (listen‑only)
	local SoundEvent = ReplicatedStorage:WaitForChild("Sound", 5)
	if not SoundEvent then
		warn("❌ 'Sound' RemoteEvent not found in ReplicatedStorage, win detection disabled.")
	end
	
	-- GUI Setup
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RoleToggleGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")
	
	-- Main container (acts like a window: title bar + pages inside)
	local mainContainer = Instance.new("Frame")
	mainContainer.Size = UDim2.new(0, 450, 0, 300) -- 40 for title + 260 for page
	mainContainer.Position = UDim2.new(0.5, -225, 0.5, -190)
	mainContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 30) -- dark gray
	mainContainer.BackgroundTransparency = 0.3                  -- semi-transparent
	mainContainer.BorderSizePixel = 0
	mainContainer.Parent = screenGui
	
	-- Shared Title Bar
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 40)
	titleBar.Position = UDim2.new(0, 0, 0, 0)
	titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	titleBar.BackgroundTransparency = 0.3
	titleBar.BorderSizePixel = 0
	titleBar.ZIndex = 2
	titleBar.Parent = mainContainer
	
	local minimizeButton = Instance.new("TextButton")
	minimizeButton.Size = UDim2.new(0, 40, 0, 40)
	minimizeButton.AnchorPoint = Vector2.new(1, 0)
	minimizeButton.Position = UDim2.new(1, -5, 0, 0)
	minimizeButton.Text = "-"
	minimizeButton.Font = Enum.Font.Arcade
	minimizeButton.TextSize = 24
	minimizeButton.TextColor3 = Color3.new(1, 1, 1)
	minimizeButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80) -- darker gray
	minimizeButton.BackgroundTransparency = 0
	minimizeButton.BorderSizePixel = 0
	minimizeButton.ZIndex = 3
	minimizeButton.Parent = titleBar
	
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -50, 1, 0)
	titleLabel.Position = UDim2.new(0, 0, 0, 0)
	titleLabel.Text = "LeBron James Endurance Script"
	titleLabel.Font = Enum.Font.Arcade
	titleLabel.TextSize = 24
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.BackgroundTransparency = 1 -- no box behind text
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.ZIndex = 3
	titleLabel.Parent = titleBar
	
	-- Utility to create buttons (bright blue accent style)
	local function createButton(text, position, parent, size)
		local button = Instance.new("TextButton")
		button.Size = size or UDim2.new(0, 200, 0, 40)
		button.Position = position
		button.Text = text
		button.BackgroundColor3 = Color3.fromRGB(100, 170, 255) -- bright blue
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Font = Enum.Font.Arcade
		button.TextSize = 20
		button.Active = true
		button.Selectable = true
		button.BorderSizePixel = 0
		button.ZIndex = 1
		button.Parent = parent
		return button
	end
	
	-- Page 1 (offset below title bar)
	local page1 = Instance.new("Frame")
	page1.Position = UDim2.new(0, 0, 0, 40) -- push down below title bar
	page1.Size = UDim2.new(1, 0, 0, 260)    -- 300 total - 40 bar = 260
	page1.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	page1.BackgroundTransparency = 0.3
	page1.BorderSizePixel = 0
	page1.ZIndex = 1
	page1.Parent = mainContainer
	
	local soloButton = createButton("SOLO MODE", UDim2.new(0, 20, 0, 60), page1)
	local onOffButton = createButton("OFF", UDim2.new(0, 230, 0, 60), page1)
	
	local usernameBox = Instance.new("TextBox")
	usernameBox.Size = UDim2.new(0, 200, 0, 40)
	usernameBox.Position = UDim2.new(0, 20, 0, 120)
	usernameBox.PlaceholderText = "Username"
	usernameBox.Font = Enum.Font.Arcade
	usernameBox.TextSize = 18
	usernameBox.TextColor3 = Color3.new(1, 1, 1)
	usernameBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50) -- solid gray
	usernameBox.BorderSizePixel = 0
	usernameBox.Parent = page1
	
	local roleBox = Instance.new("TextBox")
	roleBox.Size = UDim2.new(0, 200, 0, 40)
	roleBox.Position = UDim2.new(0, 230, 0, 120)
	roleBox.PlaceholderText = "Enter role here!"
	roleBox.Font = Enum.Font.Arcade
	roleBox.TextSize = 18
	roleBox.TextColor3 = Color3.new(1, 1, 1)
	roleBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50) -- solid gray
	roleBox.BorderSizePixel = 0
	roleBox.Parent = page1
	
	-- Smaller Next button (bottom right)
	local nextPageButton = createButton("NEXT >", UDim2.new(1, -100, 1, -40), page1, UDim2.new(0, 80, 0, 30))
	
	-- Page 2 (same offset)
	local page2 = Instance.new("Frame")
	page2.Position = UDim2.new(0, 0, 0, 40)
	page2.Size = UDim2.new(1, 0, 0, 260)
	page2.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	page2.BackgroundTransparency = 0.3
	page2.BorderSizePixel = 0
	page2.Visible = false
	page2.ZIndex = 1
	page2.Parent = mainContainer
	
	-- Back button pinned bottom-left
	local backButton = createButton("< BACK", UDim2.new(0, 20, 1, -40), page2, UDim2.new(0, 80, 0, 30))
	
	-- Auto Toxic Shake toggle
	local toxicShakeButton = createButton("Auto Toxic Shake: OFF", UDim2.new(0.5, -100, 0, 30), page2)
	toxicShakeButton.TextSize = 16
	local toxicShakeActive = false
	toxicShakeButton.MouseButton1Click:Connect(function()
		toxicShakeActive = not toxicShakeActive
		toxicShakeButton.Text = toxicShakeActive and "Auto Toxic Shake: ON" or "Auto Toxic Shake: OFF"
		if toxicShakeActive then
			task.spawn(function()
				while toxicShakeActive do
					pcall(function()
						game.ReplicatedStorage["Drink_Shake"]:InvokeServer("Toxic")
					end)
					task.wait(2)
				end
			end)
		end
	end)
	
	-- Anti-AFK button
	local antiAfkButton = createButton("Run Anti-AFK", UDim2.new(0.5, -100, 0, 80), page2)
	antiAfkButton.MouseButton1Click:Connect(function()
		local VirtualUser = game:GetService("VirtualUser")
		game:GetService("Players").LocalPlayer.Idled:Connect(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
		print("✅ Anti-AFK script executed")
	end)
	
	-- Endurance Checker label
	local enduranceLabel = Instance.new("TextLabel")
	enduranceLabel.Size = UDim2.new(0, 300, 0, 40)
	enduranceLabel.Position = UDim2.new(0.5, -150, 0, 130)
	enduranceLabel.Font = Enum.Font.Arcade
	enduranceLabel.TextSize = 18
	enduranceLabel.TextColor3 = Color3.new(1, 1, 1)
	enduranceLabel.TextStrokeTransparency = 0.8
	enduranceLabel.TextStrokeColor3 = Color3.fromRGB(0,0,0)
	enduranceLabel.BackgroundTransparency = 1 -- keep transparent so text sits cleanly
	enduranceLabel.TextXAlignment = Enum.TextXAlignment.Center
	enduranceLabel.Text = "Endurance: not found"
	enduranceLabel.ZIndex = 2
	enduranceLabel.Parent = page2
	
	-- Toxic Shake Checker label
	local shakeLabel = Instance.new("TextLabel")
	shakeLabel.Size = UDim2.new(0, 300, 0, 40)
	shakeLabel.Position = UDim2.new(0.5, -150, 0, 170)
	shakeLabel.Font = Enum.Font.Arcade
	shakeLabel.TextSize = 18
	shakeLabel.TextColor3 = Color3.new(1, 1, 1)
	shakeLabel.TextStrokeTransparency = 0.8
	shakeLabel.TextStrokeColor3 = Color3.fromRGB(0,0,0)
	shakeLabel.BackgroundTransparency = 1
	shakeLabel.TextXAlignment = Enum.TextXAlignment.Center
	shakeLabel.Text = "Toxic Shakes: not found"
	shakeLabel.ZIndex = 2
	shakeLabel.Parent = page2
	
	-- Page switching
	local lastPage = "page1"
	nextPageButton.MouseButton1Click:Connect(function()
		page1.Visible = false
		page2.Visible = true
		lastPage = "page2"
	end)
	backButton.MouseButton1Click:Connect(function()
		page2.Visible = false
		page1.Visible = true
		lastPage = "page1"
	end)
	
	-- Minimise / Maximise Logic (affects the whole container)
	local minimized = false
	local originalSize = mainContainer.Size
	local originalPos = mainContainer.Position
	local titleBarHeight = titleBar.Size.Y.Offset
	
	minimizeButton.MouseButton1Click:Connect(function()
		minimized = not minimized
		minimizeButton.Text = minimized and "+" or "-"
	
		if minimized then
			-- Hide both pages
			page1.Visible = false
			page2.Visible = false
			-- Shrink container to just the title bar
			mainContainer.Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset, 0, titleBarHeight)
			mainContainer.Position = originalPos
		else
			-- Restore whichever page was last active
			if lastPage == "page2" then
				page2.Visible = true
			else
				page1.Visible = true
			end
			mainContainer.Size = originalSize
			mainContainer.Position = originalPos
		end
	end)
	
	-- Make GUI draggable by the title bar (moves the whole container)
	local UserInputService = game:GetService("UserInputService")
	
	local function makeDraggable(dragHandle, targetFrames)
		local dragging = false
		local dragStart, startPositions = nil, {}
	
		dragHandle.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 
			or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPositions = {}
				for _, frame in ipairs(targetFrames) do
					startPositions[frame] = frame.Position
				end
			end
		end)
	
		dragHandle.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 
			or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement 
			or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				for frame, pos in pairs(startPositions) do
					frame.Position = UDim2.new(
						pos.X.Scale, pos.X.Offset + delta.X,
						pos.Y.Scale, pos.Y.Offset + delta.Y
					)
				end
			end
		end)
	end
	
	-- Apply draggable to both the title bar and the main container (so you can grab anywhere)
	makeDraggable(titleBar, {mainContainer})
	makeDraggable(mainContainer, {mainContainer})
	makeDraggable(page1, {mainContainer})
	makeDraggable(page2, {mainContainer})
	
	-- Live stat updates for Endurance and Toxic Shakes
	task.spawn(function()
		local playerInfo = workspace:FindFirstChild("Player_Information")
		local myStats = playerInfo and playerInfo:FindFirstChild(player.Name)
	
		if not myStats then
			enduranceLabel.Text = "Endurance: not found"
			shakeLabel.Text = "Toxic Shakes: not found"
			return
		end
	
		-- Toxic Shakes
		local drinksFolder = myStats:FindFirstChild("Inventory") and myStats.Inventory:FindFirstChild("Drinks")
		if drinksFolder then
			local function updateShakes()
				local count = 0
				for _, item in ipairs(drinksFolder:GetChildren()) do
					if item.Name == "T" then
						count += 1
					end
				end
				shakeLabel.Text = "Toxic Shakes: " .. count
			end
			updateShakes()
			drinksFolder.ChildAdded:Connect(updateShakes)
			drinksFolder.ChildRemoved:Connect(updateShakes)
		else
			shakeLabel.Text = "Toxic Shakes: not found"
		end
	
		-- Endurance
		local statsFolder = myStats:FindFirstChild("Stats")
		local enduranceFolder = statsFolder and statsFolder:FindFirstChild("Endurance")
		local level = enduranceFolder and enduranceFolder:FindFirstChild("Level")
		local xp = enduranceFolder and enduranceFolder:FindFirstChild("XP")
	
		if level and xp then
			local function updateEndurance()
				enduranceLabel.Text = string.format("Endurance level: %d | XP: %d", level.Value, xp.Value)
			end
			updateEndurance()
			level:GetPropertyChangedSignal("Value"):Connect(updateEndurance)
			xp:GetPropertyChangedSignal("Value"):Connect(updateEndurance)
		else
			enduranceLabel.Text = "Endurance: not found"
		end
	end)
	
	-- Rolling buffers (10 cycles) for roles 1 & 2 only
	local cycleDurations10 = { [1] = {}, [2] = {} }
	local lastCycleTime    = { [1] = nil, [2] = nil }
	
	-- Restart tokens for roles 1 & 2 only
	local restartToken     = { [1] = 0, [2] = 0 }
	
	-- Force toggle off helper
	local function forceToggleOff()
	    -- Disconnect loop + win listener(s)
	    if loopConnection and loopConnection.Connected then
	        loopConnection:Disconnect()
	        loopConnection = nil
	    end
	    if winConnection and winConnection.Connected then
	        winConnection:Disconnect()
	        winConnection = nil
	    end
	
	    -- Disconnect HRP listeners if they exist
	    if hrpAddedConn then hrpAddedConn:Disconnect() hrpAddedConn = nil end
	    if hrpRemovedConn then hrpRemovedConn:Disconnect() hrpRemovedConn = nil end
	    hrp = nil
	
	    -- If you stored CharacterAdded in a variable, clean it too:
	    if charAddedConn then charAddedConn:Disconnect() charAddedConn = nil end
	
	    -- Reset cycle tracking + restart tokens for roles 1 & 2 only
	    for r = 1, 2 do
	        cycleDurations10[r] = {}
	        lastCycleTime[r] = nil
	        restartToken[r] = 0
	    end
	
	    -- Reset state flags
	    activeRole = nil
	    isActive = false
	    won = false
	    timeoutElapsed = false
	    role1WatchdogArmed = false
	
	    -- UI feedback (guard in case buttons aren’t ready yet)
	    if onOffButton then
	        onOffButton.Text = "OFF"
	        onOffButton.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
	    end
	    if soloButton then
	        soloButton.Text = "SOLO"
	        soloButton.BackgroundColor3 = Color3.fromRGB(0, 150, 255) -- bright blue, not gray
	        soloButton.AutoButtonColor = false -- stop Roblox from tinting it gray
	    end
	
	    print("Script stopped")
	end
	
	-- Button connections
	onOffButton.MouseButton1Click:Connect(function()
	    if handleOnOffClick then
	        handleOnOffClick()
	    else
	        print("ON/OFF clicked but handler not ready yet")
	    end
	end)
	
	soloButton.MouseButton1Click:Connect(function()
	    if handleSoloClick then
	        handleSoloClick()
	    else
	        print("SOLO clicked but handler not ready yet")
	    end
	end)
	
	-- Cold start reset (initialise state once at load)
	forceToggleOff()
	
	-- Configs
	local configs = {
	    [1] = { name = "PLAYER 1: DUMMY", teleportDelay = 0.2, deathDelay = 0.2, cycleDelay = 5.6 },
	    [2] = { name = "PLAYER 2: MAIN",  teleportDelay = 0.2, deathDelay = 0.2, cycleDelay = 5.6 },
	    [3] = { name = "SOLO MODE",       teleportDelay = 0.2, deathDelay = 0.2, cycleDelay = 5.6 }
	}
	
	-- Track wins / state
	local won = false
	local timeoutElapsed = false
	
	-- Role 1 watchdog guard (per-session)
	local role1WatchdogArmed = false
	
	-- Rolling buffer (10 cycles) — ONLY roles 1 & 2
	local cycleDurations10 = { [1] = {}, [2] = {} }
	local lastCycleTime    = { [1] = nil, [2] = nil }
	
	-- Services
	local RunService = game:GetService("RunService")
	
	-- Restart Delay Parameters
	local ROLE1_TIMEOUT       = 15   -- watchdog window before restart logic
	local ROLE1_EXTRA_DELAY   = 10   -- added to average cycle
	local ROLE1_MIN_DELAY     = 10  -- minimum enforced delay
	
	local ROLE2_EXTRA_DELAY   = 25   -- added to average cycle
	local ROLE2_MIN_DELAY     = 25   -- minimum enforced delay
	local ROLE2_OFFSET        = -2   -- restart 2s earlier than baseline (tweak as needed)
	
	-- Delay Helper
	local function computeRestartDelay(role, avg)
	    if role == 1 then
	        return math.max((avg or 0) + ROLE1_EXTRA_DELAY, ROLE1_MIN_DELAY)
	    elseif role == 2 then
	        local base = math.max((avg or 0) + ROLE2_EXTRA_DELAY, ROLE2_MIN_DELAY)
	        return math.max(base + ROLE2_OFFSET, 0)
	    end
	end
	
	-- Record a completed cycle (ignore role 3 entirely)
	local function recordCycle(role)
	    if role ~= 1 and role ~= 2 then return end
	    local now = os.clock()
	    local last = lastCycleTime[role]
	    if last then
	        local duration = now - last
	        table.insert(cycleDurations10[role], duration)
	        if #cycleDurations10[role] > 10 then
	            table.remove(cycleDurations10[role], 1)
	        end
	    end
	    lastCycleTime[role] = now
	end
	
	-- Compute average cycle length (ignore role 3)
	local function getCycleAverage(role)
	    if role ~= 1 and role ~= 2 then return nil end
	    local tbl = cycleDurations10[role]
	    if not tbl or #tbl == 0 then return nil end
	    local sum = 0
	    for _, v in ipairs(tbl) do
	        sum = sum + v
	    end
	    return sum / #tbl
	end
	
	-- Per-role restart token to prevent overlapping restarts — ONLY roles 1 & 2
	local restartToken = { [1] = 0, [2] = 0 }
	
	-- Restart a role after a delay, ensuring the old loop is stopped first
	function restartRole(role, delay)
	    -- SOLO mode: no restart logic
	    if role == 3 then
	        warn("Solo mode does not utilise external parameters such as restarting.")
	        return
	    end
	
	    -- Disconnect loop + win listener(s)
	    if loopConnection and loopConnection.Connected then
	        loopConnection:Disconnect()
	        loopConnection = nil
	    end
	    if winConnection and winConnection.Connected then
	        winConnection:Disconnect()
	        winConnection = nil
	    end
	
	    isActive = false
	
	    restartToken[role] = (restartToken[role] or 0) + 1
	    local token = restartToken[role]
	
	    task.spawn(function()
	        local d = delay or 0
	        if d > 0 then waitSeconds(d) end
	
	        -- Abort if superseded or role changed
	        if restartToken[role] ~= token or activeRole ~= role then
	            print(("ℹ️ Restart for role %d skipped (superseded or role changed)"):format(role))
	            return
	        end
	
	        -- Reset averages and session flags for this role
	        cycleDurations10[role] = {}
	        lastCycleTime[role] = nil
	        won, timeoutElapsed = false, false
	
	        if role == 1 then
	            role1WatchdogArmed = false -- allow watchdog to re-arm cleanly
	        end
	
	        isActive = true
	        if type(runLoop) == "function" then runLoop(role) end
	        if type(listenForWin) == "function" then listenForWin(role) end
	
	        print(("🔄 Role %d restarted"):format(role))
	    end)
	end
	
	-- Win/timeout detection (SOLO excluded)
	function listenForWin(role)
	    if role == 3 or not SoundEvent or not SoundEvent.OnClientEvent then
	        return
	    end
	
	    if winConnection and winConnection.Connected then
	        winConnection:Disconnect()
	        winConnection = nil
	    end
	
	    if role == 1 then
	        -- Reset state fresh each session
	        won, timeoutElapsed = false, false
	        local lastWinTime = nil
	
	        winConnection = SoundEvent.OnClientEvent:Connect(function(action, data)
	            if activeRole ~= 1 then return end
	            if action == "Play" and type(data) == "table" then
	                if data.Name == "Win" or data.Name == "WinP1" then
	                    won = true
	                    timeoutElapsed = false
	                    lastWinTime = os.clock()
	                end
	            end
	        end)
	
	        if not role1WatchdogArmed and activeRole == 1 then
	            role1WatchdogArmed = true
	            print(("⌚ Role 1 watchdog armed (%ds window)"):format(ROLE1_TIMEOUT))
	
	            task.spawn(function()
	                local startTime = os.clock()
	
	                while os.clock() - startTime < ROLE1_TIMEOUT do
	                    if activeRole ~= 1 then
	                        return -- bail if role changed
	                    end
	                    waitSeconds(0.1)
	                end
	
	                -- Timeout only if no win occurred during the watchdog window
	                if (not lastWinTime or lastWinTime < startTime) and activeRole == 1 then
	                    timeoutElapsed = true
	                    local avg = getCycleAverage(1) or (configs[1] and configs[1].cycleDelay) or 0
	                    local delay = computeRestartDelay(1, avg)
	                    print(("⚠️ Role 1 timed out! restarting after %.2fs (avg=%.3f+%d)")
	                        :format(delay, avg or 0, ROLE1_EXTRA_DELAY))
	                    restartRole(1, delay)
	                end
	            end)
	        end
	
	    elseif role == 2 then
	        winConnection = SoundEvent.OnClientEvent:Connect(function(action, data)
	            if activeRole ~= 2 then return end
	            if action == "Play" and type(data) == "table" then
	                if data.Name == "WinP2" or data.Name == "Win" then
	                    won = true
	
	                    if winConnection and winConnection.Connected then
	                        winConnection:Disconnect()
	                        winConnection = nil
	                    end
	
	                    local avg = getCycleAverage(2) or (configs[2] and configs[2].cycleDelay) or 0
	                    local delay = computeRestartDelay(2, avg)
	                    print(("⚠️ Role 2 win detected! restarting after %.2fs (avg=%.3f+%d, offset=%ds) [event=%s]")
	                        :format(delay, avg or 0, ROLE2_EXTRA_DELAY, ROLE2_OFFSET, tostring(data.Name)))
	                    restartRole(2, delay)
	                end
	            end
	        end)
	    end
	end
					
	-- Core loop (drift-proofed + catch-up + HRP tracker)
	function runLoop(role)
	    local points = role == 1 and {
	        workspace.Spar_Ring1.Player1_Button.CFrame,
	        workspace.Spar_Ring4.Player1_Button.CFrame
	    } or role == 2 and {
	        workspace.Spar_Ring1.Player2_Button.CFrame,
	        workspace.Spar_Ring4.Player2_Button.CFrame
	    } or role == 3 and {
	        workspace.Spar_Ring2.Player1_Button.CFrame,
	        workspace.Spar_Ring2.Player2_Button.CFrame,
	        workspace.Spar_Ring3.Player1_Button.CFrame,
	        workspace.Spar_Ring3.Player2_Button.CFrame
	    }
	
	    if not points then
	        warn("runLoop: no points available for role " .. tostring(role))
	        return
	    end
	
	    local config = configs[role]
	    if not config then
	        warn(("Loop: missing config for role %s"):format(tostring(role)))
	        return
	    end
	
	    local index = 1
	    local phase = "teleport"
	    local phaseStart = os.clock()
	    local teleported = false
	
	    -- Track HRP without yielding
	    local hrp
	    local hrpAddedConn, hrpRemovedConn
	
	    local function updateHRP(char)
	        if hrpAddedConn then hrpAddedConn:Disconnect() hrpAddedConn = nil end
	        if hrpRemovedConn then hrpRemovedConn:Disconnect() hrpRemovedConn = nil end
	        hrp = nil
	
	        if not char then return end
	        hrp = char:FindFirstChild("HumanoidRootPart")
	
	        hrpAddedConn = char.ChildAdded:Connect(function(child)
	            if child.Name == "HumanoidRootPart" then
	                hrp = child
	            end
	        end)
	
	        hrpRemovedConn = char.ChildRemoved:Connect(function(child)
	            if child == hrp then
	                hrp = nil
	            end
	        end)
	    end
	
	    if player.Character then
	        updateHRP(player.Character)
	    end
	    player.CharacterAdded:Connect(updateHRP)
	
	    if loopConnection and loopConnection.Connected then
	        loopConnection:Disconnect()
	        loopConnection = nil
	    end
	
	    loopConnection = RunService.Heartbeat:Connect(function()
	        if activeRole ~= role or not isActive then
	            loopConnection:Disconnect()
	            loopConnection = nil
	            return
	        end
	
	        local now = os.clock()
	
	        -- teleport phase
	        while phase == "teleport" and now >= phaseStart + config.teleportDelay do
	            if hrp then
	                hrp.CFrame = points[index]
	                teleported = true
	                phase = "kill"
	            end
	            phaseStart += config.teleportDelay
	        end
	
	        -- kill phase
	        while phase == "kill" and now >= phaseStart + config.deathDelay do
	            if teleported then
	                local char = player.Character
	                if char then
	                    pcall(function() char:BreakJoints() end)
	                end
	                teleported = false
	                phase = "respawn"
	            end
	            phaseStart += config.deathDelay
	        end
	
	        -- rewspawn phase
	        if phase == "respawn" then
	            -- give HRP up to 5s to appear
	            if hrp then
	                if (role == 1 or role == 2) and recordCycle then
	                    recordCycle(role)
	                end
	                phase = "wait"
	                phaseStart = now
	            elseif now >= phaseStart + 5 then
	                warn("Respawn timeout, forcing wait phase")
	                phase = "wait"
	                phaseStart = now
	            end
	        end
	
	        -- wait phase
	        while phase == "wait" and now >= phaseStart + config.cycleDelay do
	            phase = "teleport"
	            phaseStart += config.cycleDelay
	            index = index % #points + 1
	        end
	    end)
	end

	local Players = game:GetService("Players")
	local graceSeconds = 12
	
	-- helper: case-insensitive lookup
	local function findPlayerByName(name)
	    if not name or name == "" then return nil end
	    for _, plr in ipairs(Players:GetPlayers()) do
	        if plr.Name:lower() == name:lower() then
	            return plr
	        end
	    end
	end
	
	local function startSoloMonitor(partnerName)
	    if activeRole ~= 1 or not isActive then return end
	    if not partnerName or partnerName == "" then
	        warn("⚠️ No partner name provided, switching to solo immediately")
	        if handleSoloClick then task.defer(handleSoloClick) end
	        return
	    end
	
	    local stablePartnerId, graceEnd
	    local inGrace, soloTriggered = false, false
	    local rejoinConn
	
	    local function switchToSolo(reason)
	        if soloTriggered then return end
	        soloTriggered = true
	        print(("⚠️ %s → switching to SOLO"):format(reason))
	        if handleSoloClick then task.defer(handleSoloClick) end
	        if rejoinConn then rejoinConn:Disconnect() rejoinConn = nil end
	    end
	
	    task.spawn(function()
	        while not soloTriggered and activeRole == 1 and isActive do
	            local partner = findPlayerByName(partnerName)
	            if partner then
	                stablePartnerId = stablePartnerId or partner.UserId
	                inGrace, graceEnd = false, nil
	            else
	                if not inGrace then
	                    print(("⚠️ Partner %s missing! %ds grace window started"):format(partnerName, graceSeconds))
	                    inGrace, graceEnd = true, os.clock() + graceSeconds
	                    if rejoinConn then rejoinConn:Disconnect() rejoinConn = nil end
	                    rejoinConn = Players.PlayerAdded:Connect(function(newPlr)
	                        if inGrace and (newPlr.UserId == stablePartnerId or newPlr.Name:lower() == partnerName:lower()) then
	                            print("✅ Partner rejoined within timeframe.")
	                            inGrace, graceEnd = false, nil
	                            rejoinConn:Disconnect()
	                            rejoinConn = nil
	                        end
	                    end)
	                elseif os.clock() >= graceEnd then
	                    switchToSolo("Partner did not return within grace window")
	                    break
	                end
	            end
	            task.wait(0.25)
	        end
	    end)
	end
	
	-- Role validation and assignment
	local function validateAndAssignRole()
	    local targetName = usernameBox.Text
	    local roleCommand = roleBox.Text
	    local targetPlayer = findPlayerByName(targetName)
	
	    if not targetPlayer or (roleCommand ~= "#AFK" and roleCommand ~= "#AFK2") then
	        print("Validation failed")
	        onOffButton.Text = "Validation failed"
	        onOffButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	        task.delay(3, function() forceToggleOff() end)
	        return
	    end
	
	    if roleCommand == "#AFK" then
	        activeRole = 1
	        role1WatchdogArmed = false
	        startSoloMonitor(targetName)  -- start monitor here
	    elseif roleCommand == "#AFK2" then
	        activeRole = 2
	    end
	
	    won, timeoutElapsed = false, false
	    resetCycles(activeRole)
	
	    isActive = true
	    onOffButton.Text = "ON"
	    onOffButton.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
	
	    runLoop(activeRole)
	
	    if activeRole == 1 or activeRole == 2 then
	        if listenForWin then
	            listenForWin(activeRole)
	        else
	            warn("validateAndAssignRole: listenForWin not assigned yet")
	        end
	    end
	end
	
	-- Reset cycle tracking for a given role (roles 1 & 2 only)
	local function resetCycles(role)
	    if role ~= 1 and role ~= 2 then return end
	    cycleDurations10[role] = {}
	    lastCycleTime[role] = nil
	end
	
	-- Role validation and assignment
	local function validateAndAssignRole()
	    local targetName = usernameBox.Text
	    local roleCommand = roleBox.Text
	    local targetPlayer = findPlayerByName(targetName)  -- case-insensitive lookup
	
	    -- Validation
	    if not targetPlayer or (roleCommand ~= "#AFK" and roleCommand ~= "#AFK2") then
	        print("Validation failed")
	        onOffButton.Text = "Validation failed"
	        onOffButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	        task.delay(3, function() forceToggleOff() end)
	        return
	    end
	
	    -- Assign role
	    if roleCommand == "#AFK" then
	        activeRole = 1
	        role1WatchdogArmed = false
	        startSoloMonitor(targetName)  -- start monitor here
	    elseif roleCommand == "#AFK2" then
	        activeRole = 2
	    end
	
	    -- Reset state + cycles
	    won, timeoutElapsed = false, false
	    resetCycles(activeRole)
	
	    isActive = true
	    onOffButton.Text = "ON"
	    onOffButton.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
	
	    -- Start loop
	    runLoop(activeRole)
	
	    -- Only arm win listeners for roles 1 & 2
	    if activeRole == 1 or activeRole == 2 then
	        if listenForWin then
	            listenForWin(activeRole)
	        else
	            warn("listenForWin not assigned yet")
	        end
	    end
	end
	
	-- Assign handlers
	handleOnOffClick = function()
	    if activeRole then
	        forceToggleOff()
	    else
	        validateAndAssignRole()
	    end
	end
	
	handleSoloClick = function()
	    -- Cleanly stop any existing loop/state
	    forceToggleOff()
	
	    -- Explicitly set SOLO state
	    activeRole, isActive = 3, true
	    won, timeoutElapsed = false, false
	
	    -- Update button appearance
	    onOffButton.Text = "SOLO mode: ON"
	    onOffButton.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
	    onOffButton.AutoButtonColor = false   -- prevent Roblox gray tint
	    onOffButton.TextColor3 = Color3.new(1, 1, 1)
	
	    -- Guard: ensure character is ready before first Solo cycle
	    local char = player.Character or player.CharacterAdded:Wait()
	    char:WaitForChild("Humanoid")
	    char:WaitForChild("HumanoidRootPart")
	
	    -- Start the SOLO loop
	    runLoop(3)
	end
end
