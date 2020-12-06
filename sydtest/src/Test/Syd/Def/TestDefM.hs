{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE IncoherentInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Test.Syd.Def.TestDefM where

import Control.Monad.RWS.Strict
import Data.DList (DList)
import qualified Data.DList as DList
import Data.Maybe
import Data.Text (Text)
import qualified Data.Text as T
import Test.QuickCheck.IO ()
import Test.Syd.OptParse
import Test.Syd.Run
import Test.Syd.SpecDef

-- | A synonym for easy migration from hspec
type Spec = SpecWith ()

-- | A synonym for easy migration from hspec
type SpecWith a = SpecM a ()

-- | A synonym for easy migration from hspec
type SpecM a b = TestDefM '[] a b

-- | The test definition monad
--
-- This type has three parameters:
--
-- * @a@: The type of the result of `aroundAll`
-- * @b@: The type of the result of `around`
-- * @c@: The result
--
-- In practice, all of these three parameters should be '()' at the top level.
newtype TestDefM a b c = TestDefM
  { unTestDefM :: RWST TestRunSettings (TestForest a b) () IO c
  }
  deriving (Functor, Applicative, Monad, MonadIO, MonadReader TestRunSettings, MonadWriter (TestForest a b), MonadState ())

execTestDefM :: Settings -> TestDefM a b c -> IO (TestForest a b)
execTestDefM sets = fmap snd . runTestDefM sets

runTestDefM :: Settings -> TestDefM a b c -> IO (c, TestForest a b)
runTestDefM sets defFunc = do
  let func = unTestDefM defFunc
  (a, _, testForest) <- runRWST func (toTestRunSettings sets) () -- TODO allow passing in settings from the command-line
  let testForest' = case settingFilter sets of
        Nothing -> testForest
        Just f -> filterTestForest f testForest
  pure (a, testForest')

toTestRunSettings :: Settings -> TestRunSettings
toTestRunSettings Settings {..} =
  TestRunSettings
    { testRunSettingChildProcessOverride = testRunSettingChildProcessOverride defaultTestRunSettings,
      testRunSettingSeed = settingSeed,
      testRunSettingMaxSuccess = settingMaxSuccess,
      testRunSettingMaxSize = settingMaxSize,
      testRunSettingMaxDiscardRatio = settingMaxDiscard,
      testRunSettingMaxShrinks = settingMaxShrinks
    }

filterTestForest :: Text -> SpecDefForest a b c -> SpecDefForest a b c
filterTestForest f = fromMaybe [] . goForest DList.empty
  where
    goForest :: DList Text -> SpecDefForest a b c -> Maybe (SpecDefForest a b c)
    goForest ts sdf = do
      let sdf' = mapMaybe (goTree ts) sdf
      guard $ not $ null sdf'
      pure sdf'
    goTree :: DList Text -> SpecDefTree a b c -> Maybe (SpecDefTree a b c)
    goTree dl = \case
      DefSpecifyNode t td e -> do
        let tl = DList.toList (DList.snoc dl t)
        guard $ f `T.isInfixOf` (T.intercalate "." tl)
        pure $ DefSpecifyNode t td e
      DefDescribeNode t sdf -> DefDescribeNode t <$> goForest (DList.snoc dl t) sdf
      DefWrapNode func sdf -> DefWrapNode func <$> goForest dl sdf
      DefBeforeAllNode func sdf -> DefBeforeAllNode func <$> goForest dl sdf
      DefBeforeAllWithNode func sdf -> DefBeforeAllWithNode func <$> goForest dl sdf
      DefAroundAllNode func sdf -> DefAroundAllNode func <$> goForest dl sdf
      DefAroundAllWithNode func sdf -> DefAroundAllWithNode func <$> goForest dl sdf
      DefAfterAllNode func sdf -> DefAfterAllNode func <$> goForest dl sdf
      DefParallelismNode func sdf -> DefParallelismNode func <$> goForest dl sdf