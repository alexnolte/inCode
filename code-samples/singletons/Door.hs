#!/usr/bin/env stack
-- stack --install-ghc runghc --resolver nightly-2017-07-31

{-# LANGUAGE DataKinds      #-}
{-# LANGUAGE GADTs          #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase     #-}
{-# LANGUAGE TypeInType     #-}

import Data.Kind

data DoorState = Opened | Closed | Locked
  deriving (Show, Eq)

data Door (s :: DoorState) = UnsafeMkDoor

closeDoor :: Door 'Opened -> Door 'Closed
closeDoor UnsafeMkDoor = UnsafeMkDoor

lockDoor :: Door 'Closed -> Door 'Locked
lockDoor UnsafeMkDoor = UnsafeMkDoor

openDoor :: Door 'Closed -> Door 'Opened
openDoor UnsafeMkDoor = UnsafeMkDoor

data SingDS :: DoorState -> Type where
    SOpened :: SingDS 'Opened
    SClosed :: SingDS 'Closed
    SLocked :: SingDS 'Locked

doorStatus :: SingDS s -> Door s -> DoorState
doorStatus = \case
    SOpened -> -- in this branch, `s` is `'Opened`
        \_ -> Opened
    SClosed -> -- in this branch, `s` is `'Closed`
        \_ -> Closed
    SLocked -> -- in this branch, `s` is `'Locked`
        \_ -> Locked

lockAnyDoor :: SingDS s -> (Door s -> Door 'Locked)
lockAnyDoor = \case
    SOpened -> lockDoor . closeDoor
    SClosed -> lockDoor
    SLocked -> id

class SingDSI s where
    singDS :: SingDS s

instance SingDSI 'Opened where
    singDS = SOpened
instance SingDSI 'Closed where
    singDS = SClosed
instance SingDSI 'Locked where
    singDS = SLocked

doorStatus_ :: SingDSI s => Door s -> DoorState
doorStatus_ = doorStatus singDS

lockAnyDoor_ :: SingDSI s => Door s -> Door 'Locked
lockAnyDoor_ = lockAnyDoor singDS

mkDoor :: SingDS s -> Door s
mkDoor = \case
    SOpened -> UnsafeMkDoor
    SClosed -> UnsafeMkDoor
    SLocked -> UnsafeMkDoor

data SomeDoor :: Type where
    MkSomeDoor :: SingDS s -> Door s -> SomeDoor

closeSomeDoor :: SomeDoor -> Maybe SomeDoor
closeSomeDoor = \case
    MkSomeDoor SOpened d -> Just $ MkSomeDoor SClosed (closeDoor d)
    MkSomeDoor SClosed _ -> Nothing
    MkSomeDoor SLocked _ -> Nothing

lockAnySomeDoor :: SomeDoor -> SomeDoor
lockAnySomeDoor (MkSomeDoor s d) = MkSomeDoor SLocked (lockAnyDoor s d)

mkSomeDoor :: DoorState -> SomeDoor
mkSomeDoor = \case
    Opened -> MkSomeDoor SOpened (mkDoor SOpened)
    Closed -> MkSomeDoor SClosed (mkDoor SClosed)
    Locked -> MkSomeDoor SLocked (mkDoor SLocked)

main :: IO ()
main = return ()
