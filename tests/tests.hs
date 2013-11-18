-- |
-- Copyright: (C) 2013 Amgen, Inc.
--
-- Tests. Run H on a number of R programs of increasing size and complexity,
-- comparing the output of H with the output of R.

module Main where

import Test.Tasty hiding (defaultMain)
import Test.Tasty.Golden.Advanced
import Test.Tasty.Golden.Manage

import System.IO
import System.Process
import System.FilePath

import Control.Monad (guard)
import Control.Monad.Trans
import Control.Applicative ((<$>))
import           Data.Text (Text)
import qualified Data.Text    as T

invokeR :: FilePath -> ValueGetter r Text
invokeR fp = do
    inh <- liftIO $ openFile fp ReadMode
    (_, Just outh, _, _) <- liftIO $ createProcess $ (proc "R" ["--vanilla","--silent","--slave"])
      { std_out = CreatePipe
      , std_in = UseHandle inh
      }
    liftIO $ T.pack <$> hGetContents outh


invokeH :: FilePath -> ValueGetter r Text
invokeH fp = do
    -- Logic:
    --
    --    1. Run translation process that will output translation result to the
    --    pipe.
    --
    --    XXX: in general case when multifile translation will be enabled we
    --    will have to use files that were generated by H
    --
    --    2. Save file to the temporary module
    --
    --    3. Call ghci on resulting file
    --
    (_, Just outh1, _, _) <- liftIO $ createProcess $ (proc "./dist/build/H/H" ["--ghci",fp])
      { std_out = CreatePipe }
    (_, Just outh2, _, _) <- liftIO $ createProcess $ (proc "sh" ["tests/ghciH.sh","-v0"])
      { std_out = CreatePipe
      , std_in = UseHandle outh1 }
    liftIO $ T.pack <$> hGetContents outh2

scriptCase :: TestName
           -> FilePath
           -> TestTree
scriptCase name scriptPath =
    goldenTest
      name
      (invokeR scriptPath)
      (invokeH scriptPath)
      (\outputR outputH -> return $ do
         let a = T.lines outputR
             b = T.lines outputH
         -- Continue only if values don't match. If they do, then there's
         -- 'Nothing' to do...
         guard $ not $ and (zipWith compareValues a b) && length a == length b
         return $ unlines ["Outputs don't match."
                          , "R: "
                          , T.unpack outputR
                          , "H: "
                          , T.unpack outputH
                          ])
      (const $ return ())
  where
    -- Compare Haskell and R outputs:
    -- This function assumes that output is a vector string
    --    INFO Value1 Value2 .. ValueN
    -- where INFO is [OFFSET]. For decimals we are checking if
    -- they are equal with epsilon 1e-6, this is done because R
    -- output is not very predictable it can output up to 6
    -- characters or round them.
    compareValues :: Text -> Text -> Bool
    compareValues r h =
      let (r': rs') = T.words r
          (h': hs') = T.words h
      in (r' == h') && (all eqEpsilon $ zip (map (read . T.unpack) rs' :: [Double]) (map (read . T.unpack) hs' :: [Double]))
    eqEpsilon :: (Double, Double) -> Bool
    eqEpsilon (a, b) = (a - b < 1e-6) && (a - b > (-1e-6))


integrationTests :: TestTree
integrationTests = testGroup "Integration tests"
  [ scriptCase "Trivial (empty) script" $
      "tests" </> "R" </> "empty.R"
  -- TODO: enable in relevant topic branches.
  , scriptCase "Simple arithmetic" $
       "tests" </> "R" </> "arith.R"
  , scriptCase "Simple arithmetic on vectors" $
       "tests" </> "R" </> "arith-vector.R"
  -- , scriptCase "Functions - factorial" $
  --     "tests" </> "R" </> "fact.R"
  -- , scriptCase "Functions - Fibonacci sequence" $
  --     "tests" </> "R" </> "fib.R"
  ]

tests :: TestTree
tests = testGroup "Tests" [integrationTests]

main :: IO ()
main = defaultMain tests
