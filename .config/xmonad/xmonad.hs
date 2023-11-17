import XMonad
import XMonad.Util.EZConfig (additionalKeysP)
import XMonad.Util.Ungrab

main :: IO ()
main = xmonad $ def
  { modMask = mod4Mask }
  `additionalKeysP`
  [
  ("M-<Space>", spawn "dmenu_run -i -nb '#191919' -nf '#fea63c' -sb '#fea63c' -sf '#191919' -fn 'Terminus:bold:pixelsize=18' ") 
  ,("M-<Return>", spawn "alacritty")
  ,("M-S-<Return>", spawn "dolphin")
  ]


