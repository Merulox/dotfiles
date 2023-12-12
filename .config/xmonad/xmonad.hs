--
-- xmonad example config file.
--
-- A template showing all available configuration hooks,
-- and how to override the defaults in your own xmonad.hs conf file.
--
-- Normally, you'd only override those defaults you care about.
--

import XMonad
import Data.Monoid
import System.Exit
import XMonad.Actions.CycleWS
import XMonad.Actions.NoBorders
import XMonad.Actions.UpdatePointer 
import XMonad.Actions.WindowGo
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.ManageDocks
import XMonad.Layout.Accordion
import XMonad.Layout.ResizableTile
import XMonad.Layout.Spacing
import XMonad.Layout.ThreeColumns
import XMonad.Layout.ToggleLayouts
import XMonad.Layout.TwoPane
import XMonad.ManageHook
import XMonad.Util.EZConfig 
import XMonad.Util.NamedScratchpad
import XMonad.Util.SpawnOnce
import XMonad.Util.Run

import qualified XMonad.StackSet as W
import qualified Data.Map        as M

-- The preferred terminal program, which is used in a binding below and by
-- certain contrib modules.
--
myTerminal      = "alacritty"

-- Whether focus follows the mouse pointer.
myFocusFollowsMouse :: Bool
myFocusFollowsMouse = True

-- Whether clicking on a window to focus also passes the click to the window
myClickJustFocuses :: Bool
myClickJustFocuses = False

-- Width of the window border in pixels.
--
myBorderWidth   = 2

-- modMask lets you specify which modkey you want to use. The default
-- is mod1Mask ("left alt").  You may also consider using mod3Mask
-- ("right alt"), which does not conflict with emacs keybindings. The
-- "windows key" is usually mod4Mask.
--
myModMask       = mod4Mask

-- The default number of workspaces (virtual screens) and their names.
-- By default we use numeric strings, but any string may be used as a
-- workspace name. The number of workspaces is determined by the length
-- of this list.
--
-- A tagging example:
--
-- > workspaces = ["web", "irc", "code" ] ++ map show [4..9]
--
myWorkspaces :: [String]
myWorkspaces    = ["1","2","3","4","5","6","7","8","9","10","11","12","13","14","15","16","17","18","19","20"]

-- Border colors for unfocused and focused windows, respectively.
--
myNormalBorderColor  = "#dddddd"
myFocusedBorderColor = "#ff0000"


scratchpads = [
-- run htop in xterm, find it by title, use default floating window placement
    NS "htop" "alacritty -e htop" (title =? "htop") defaultFloating ,

-- run stardict, find it by class name, place it in the floating window
-- 1/6 of screen width from the left, 1/6 of screen height
-- from the top, 2/3 of screen width by 2/3 of screen height
    NS "stardict" "stardict" (className =? "Stardict")
        (customFloating $ W.RationalRect (1/6) (1/6) (2/3) (2/3)) ,

-- run gvim, find by role, don't float
    NS "notes" "nvim --role notes ~/notes.txt" (role =? "notes") nonFloating ] where role = stringProperty "WM_WINDOW_ROLE"

toggleFull = withFocused (\windowId -> do    {       
   floats <- gets (W.floating . windowset);        
   if windowId `M.member` floats        
   then do     
       withFocused $ toggleBorder           
       withFocused $ windows . W.sink        
   else do     
       withFocused $ toggleBorder           
       withFocused $  windows . (flip W.float $ W.RationalRect 0 0 1 1)    })


------------------------------------------------------------------------
-- Key bindings. Add, modify or remove key bindings here.
--
-- myKeys conf@(XConfig {XMonad.modMask = modm}) = M.fromList $
myKeys conf@(XConfig {XMonad.modMask = modm}) = M.fromList $ 

    -- app shortcuts
    [ ((modm,               xK_Return), spawn $ XMonad.terminal conf)
    , ((modm .|. shiftMask, xK_Return), spawn "dolphin")
    , ((modm,               xK_space ), spawn "dmenu_run -i  -sb '#1B6FC6'  -fn 'Terminus:bold:pixelsize=16'")
    , ((modm .|. controlMask,xK_space), spawn "j4-dmenu-desktop")
    --, ((modm, 

    -- close focused window
    , ((modm .|. shiftMask, xK_c     ), kill)

     -- Rotate through the available layout algorithms
    , ((modm .|. shiftMask, xK_m), sendMessage NextLayout)

    --  Reset the layouts on the current workspace to default
    --, ((modm .|. shiftMask, xK_space ), setLayout $ XMonad.layoutHook conf)

    -- Resize viewed windows to the correct size
    , ((modm,               xK_n     ), refresh)

    -- Move focus to the next window
    , ((modm,               xK_Down  ), windows W.focusDown)

    -- Move focus to the previous window
    , ((modm,               xK_Up    ), windows W.focusUp  )

    -- Move focus to the master window
    , ((modm,               xK_u     ), windows W.focusMaster  )

    -- Swap the focused window and the master window
    , ((modm .|. shiftMask, xK_u     ), windows W.swapMaster)

    -- Swap the focused window with the next window
    , ((modm .|. controlMask, xK_Down), windows W.swapDown  )

    -- Swap the focused window with the previous window
    , ((modm .|. controlMask, xK_Up  ), windows W.swapUp    )

    -- Shrink the master area
    , ((modm .|. shiftMask, xK_Left  ), sendMessage Shrink)

    -- Expand the master area
    , ((modm .|. shiftMask, xK_Right ), sendMessage Expand)
     
    -- Slave Height
   -- , ((modm .|. shiftMask, xK_Up    ), sendMessage $)
   -- , ((modm .|. shiftMask, xK_Down  ), sendMessage $)
    
    -- Push window back into tiling
    , ((modm,               xK_t     ), withFocused $ windows . W.sink)

    -- Toggle fullscreen
    , ((modm,               xK_m     ), toggleFull)
    -- Toggle xmobar
    , ((modm,               xK_b     ), sendMessage ToggleStruts)

    -- Increment the number of windows in the master area
    , ((modm              , xK_comma ), sendMessage (IncMasterN 1))

    -- Deincrement the number of windows in the master area
    , ((modm              , xK_period), sendMessage (IncMasterN (-1)))

    -- Toggle the status bar gap
    -- Use this binding with avoidStruts from Hooks.ManageDocks.
    -- See also the statusBar function from Hooks.DynamicLog.
    --
    -- , ((modm              , xK_b     ), sendMessage ToggleStruts)

    -- Quit xmonad
    , ((modm .|. shiftMask, xK_r     ), io (exitWith ExitSuccess))

    -- Restart xmonad
    , ((modm.|. controlMask,  xK_r   ), spawn "xmonad --recompile; xmonad --restart")

    -- next monitor
    , ((modm,               xK_y     ), nextScreen)  -- Switch focus to the next monitor
    , ((modm .|. shiftMask, xK_y     ), shiftNextScreen) -- Move window to the next monitor


    -- Scratchpads
    , ((modm .|. controlMask .|. shiftMask, xK_t), namedScratchpadAction scratchpads "htop")
    , ((modm .|. controlMask .|. shiftMask, xK_s), namedScratchpadAction scratchpads "stardict")
    , ((modm .|. controlMask .|. shiftMask, xK_n), namedScratchpadAction scratchpads "notes")

    -- Run xmessage with a summary of the default keybindings (useful for beginners)
    --, ((modm .|. shiftMask, xK_slash ), spawn ("echo \"" ++ help ++ "\" | xmessage -file -"))
    ]
    ++

    --
    -- mod-[1..9], Switch to workspace N
    -- mod-shift-[1..9], Move client to workspace N
    --
    [((m .|. modm, k), windows $ f i)
        | (i, k) <- zip (XMonad.workspaces conf) [xK_1 .. xK_9]
        , (f, m) <- [(W.greedyView, 0), (W.shift, shiftMask)]]
    ++

    -- Move to workspaces 10-19 with mod+0 and mod+fn keys 
    [((modm, k), windows $ W.greedyView i)
        | (i, k) <- zip (drop 9 myWorkspaces) [xK_0, xK_F1, xK_F2, xK_F3, xK_F4, xK_F5, xK_F6, xK_F7, xK_F8,  xK_F9]
    ]
    ++
   
    -- Move focused window to workspaces 10-19 using mod+shift+0 and mod+Shift+fn keys
    [((modm .|. shiftMask, k), windows $ W.shift i)
        | (i, k) <- zip (drop 9 myWorkspaces) [xK_0, xK_F1, xK_F2, xK_F3, xK_F4, xK_F5, xK_F6, xK_F7, xK_F8,  xK_F9]
    ]
------------------------------------------------------------------------
-- Mouse bindings: default actions bound to mouse events
--
myMouseBindings (XConfig {XMonad.modMask = modm}) = M.fromList $

    -- mod-button1, Set the window to floating mode and move by dragging
    [ ((modm, button1), (\w -> focus w >> mouseMoveWindow w
                                       >> windows W.shiftMaster))

    -- mod-button2, Raise the window to the top of the stack
    , ((modm, button2), (\w -> focus w >> windows W.shiftMaster))

    -- mod-button3, Set the window to floating mode and resize by dragging
    , ((modm, button3), (\w -> focus w >> mouseResizeWindow w
                                       >> windows W.shiftMaster))

    -- you may also bind events to the mouse scroll wheel (button4 and button5)
    ]

------------------------------------------------------------------------
-- Layouts:

-- You can specify and transform your layouts by modifying these values.
-- If you change layout bindings be sure to use 'mod-shift-space' after
-- restarting (with 'mod-q') to reset your layout state to the new
-- defaults, as xmonad preserves your old layout settings by default.
--
-- The available layouts.  Note that each layout is separated by |||,
-- which denotes layout choice.
--
myLayout = avoidStruts $ spacing 5 (ResizableTall 1 (5/100) (1/2) [] ||| Mirror tiled ||| ThreeColMid 1 (3/100) (1/2) ||| Accordion ||| TwoPane (3/100) (1/2)  |||Full)
  where
     -- default tiling algorithm partitions the screen into two panes
     tiled   = Tall nmaster delta ratio

     -- The default number of windows in the master pane
     nmaster = 1

     -- Default proportion of screen occupied by master pane
     ratio   = 1/2

     -- Percent of screen to increment by when resizing panes
     delta   = 5/100

------------------------------------------------------------------------
-- Window rules:

-- Execute arbitrary actions and WindowSet manipulations when managing
-- a new window. You can use this to, for example, always float a
-- particular program, or have a client always appear on a particular
-- workspace.
--
-- To find the property name associated with a program, use
-- > xprop | grep WM_CLASS
-- and click on the client you're interested in.
--
-- To match on the WM_NAME, you can use 'title' in the same way that
-- 'className' and 'resource' are used below.
--
myManageHook = composeAll
    [ className =? "MPlayer"        --> doFloat
    , className =? "Gimp"           --> doFloat
    , className =? "kcalc"          --> doFloat
    , className =? "systemmonitor"  --> doFloat
    , className =? "Artha"  --> doFloat
    , resource  =? "desktop_window" --> doIgnore
    , resource  =? "kdesktop"       --> doIgnore 
    , namedScratchpadManageHook scratchpads
    , manageDocks
    , manageHook def
    ]  


------------------------------------------------------------------------
-- Event handling

-- * EwmhDesktops users should change this to ewmhDesktopsEventHook
--
-- Defines a custom handler function for X Events. The function should
-- return (All True) if the default handler is to be run afterwards. To
-- combine event hooks use mappend or mconcat from Data.Monoid.
--
myEventHook = mempty

------------------------------------------------------------------------
-- Status bars and logging

-- Perform an arbitrary action on each internal state change or X event.
-- See the 'XMonad.Hooks.DynamicLog' extension for examples.
--
myLogHook = dynamicLog
            >> updatePointer (0.5, 0.5) (0, 0)

------------------------------------------------------------------------
-- Startup hook

-- Perform an arbitrary action each time xmonad starts or is restarted
-- with mod-q.  Used by, e.g., XMonad.Layout.PerWorkspace to initialize
-- per-workspace layout choices.
--
-- By default, do nothing.
myStartupHook = do
        spawnOnce "feh --bg-fil ~/pictures/wallpapers/Background-touhou.png &"
        spawnOnce "picom &"
        spawnOnce "~/.config/xmonad/scripts/xrandr.sh"




------------------------------------------------------------------------
-- Now run xmonad with all the defaults we set up.

-- Run xmonad with the settings you specify. No need to modify this.
--
main = do
  xmproc <- spawnPipe "xmobar -x 0 ~/.config/xmobar/xmobar.config"
  xmonad $ docks defaults  
   { logHook = dynamicLogWithPP xmobarPP
        { ppOutput = hPutStrLn xmproc
        , ppOrder = \(ws:_:t:_) -> [ws, t]
        }
    -- Other configurations...
    } 

-- A structure containing your configuration settings, overriding
-- fields in the default config. Any you don't override, will
-- use the defaults defined in xmonad/XMonad/Config.hs
--
-- No need to modify this.
--
defaults = def {
      -- simple stuff
        terminal           = myTerminal,
        focusFollowsMouse  = myFocusFollowsMouse,
        clickJustFocuses   = myClickJustFocuses,
        borderWidth        = myBorderWidth,
        modMask            = myModMask,
        workspaces         = myWorkspaces,
        normalBorderColor  = myNormalBorderColor,
        focusedBorderColor = myFocusedBorderColor,

      -- key bindings
        keys               = myKeys,
        mouseBindings      = myMouseBindings,

      -- hooks, layouts
        layoutHook         = myLayout,
        manageHook         = myManageHook,
        handleEventHook    = myEventHook,
        logHook            = myLogHook,
        startupHook        = myStartupHook
    }

-- | Finally, a copy of the default bindings in simple textual tabular format.
--help :: String
--help = unlines ["The default modifier key is 'alt'. Default keybindings:",
--    "",
--    "-- launching and killing programs",
--    "mod-Shift-Enter  Launch xterminal",
--    "mod-p            Launch dmenu",
--    "mod-Shift-p      Launch gmrun",
--    "mod-Shift-c      Close/kill the focused window",
--    "mod-Space        Rotate through the available layout algorithms",
--    "mod-Shift-Space  Reset the layouts on the current workSpace to default",
--    "mod-n            Resize/refresh viewed windows to the correct size",
--    "",
--    "-- move focus up or down the window stack",
--    "mod-Tab        Move focus to the next window",
--    "mod-Shift-Tab  Move focus to the previous window",
--    "mod-j          Move focus to the next window",
--    "mod-k          Move focus to the previous window",
--    "mod-m          Move focus to the master window",
--    "",
--    "-- modifying the window order",
--    "mod-Return   Swap the focused window and the master window",
--    "mod-Shift-j  Swap the focused window with the next window",
--    "mod-Shift-k  Swap the focused window with the previous window",
--    "",
--    "-- resizing the master/slave ratio",
--    "mod-h  Shrink the master area",
--    "mod-l  Expand the master area",
--    "",
--    "-- floating layer support",
--    "mod-t  Push window back into tiling; unfloat and re-tile it",
--    "",
--    "-- increase or decrease number of windows in the master area",
--    "mod-comma  (mod-,)   Increment the number of windows in the master area",
--    "mod-period (mod-.)   Deincrement the number of windows in the master area",
--    "",
--    "-- quit, or restart",
--    "mod-Shift-q  Quit xmonad",
--    "mod-q        Restart xmonad",
--    "mod-[1..9]   Switch to workSpace N",
--    "",
--    "-- Workspaces & screens",
--    "mod-Shift-[1..9]   Move client to workspace N",
--    "mod-{w,e,r}        Switch to physical/Xinerama screens 1, 2, or 3",
--    "mod-Shift-{w,e,r}  Move client to screen 1, 2, or 3",
--    "",
--    "-- Mouse bindings: default actions bound to mouse events",
--    "mod-button1  Set the window to floating mode and move by dragging",
--    "mod-button2  Raise the window to the top of the stack",
--    "mod-button3  Set the window to floating mode and resize by dragging"]
