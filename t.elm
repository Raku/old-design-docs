-- Click on the righthand screen and start pressing keys!

import Char
import Graphics.Element exposing (..)
import Keyboard
import Signal exposing (..)
import String

-- foldr : (Char -> b -> b) -> b -> String -> b
-- foldp : (a -> state -> state) -> state -> Signal a -> Signal state
--  foldp (\click total -> total + 1) 0 Mouse.clicks
-- map : (a -> result) -> Signal a -> Signal result





main : Signal Element
main =   Signal.map display state
  

state: Signal String
state =   foldp  String.cons "" chars
 
chars: Signal String
chars =   map (\keycode -> toString <| Char.fromCode keycode ) Keyboard.presses 


display : String -> Element
display str =
  flow right
    [ show "The current state is : "
    , show str
    ]