{-# LANGUAGE DataKinds, TypeOperators, PolyKinds #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
module Spark.Par.Types where

import Control.Distributed.Process
import Control.Distributed.Process.Async
import Control.Monad
import Control.Applicative
import Data.Functor
import Data.IORef
import Data.Typeable
import Control.DeepSeq

newtype Block a = Block (Process [a])

data RDD :: * -> * where
  DataRDD :: [Block a] -> RDD a
  MapRDD :: Closure (a -> b) -> RDD a -> RDD b
  FilterRDD :: Closure (a -> Bool) -> RDD a -> RDD a
  ReduceRDD :: Ord k => Closure (k -> v -> v -> u) -> RDD (k, v) -> RDD (k, u)


-- | Convert a closure into a list of 
initRDD :: Typeable a => [Closure [a]] -> RDD a
initRDD = DataRDD . map (Block . unClosure)


-- | IORef to store status of completed processes
newtype NIVar a = NIVar (IORef (NIVarContents a))

-- | Equality for NIVars is physical equality, as with other reference types.
instance Eq (NIVar a) where
  (NIVar r1) == (NIVar r2) = r1 == r2

-- Forcing evaluation of a IVar is fruitless.
instance NFData (NIVar a) where
  rnf _ = ()

data NIVarContents a = Full (AsyncResult a)
                     | Empty
                     | Blocked (Async a) [Process a -> Plan]

new :: NodePar (NIVar a)
new = NodePar $ New Empty

put :: NIVar a -> Process a -> NodePar ()
put v i = NodePar $ \c -> Put v i (c ())

get :: NIVar a -> NodePar a
get v = NodePar $ \c -> Get v c

fork :: NodePar () -> NodePar ()
fork p = NodePar $
  \c -> Fork (runNodePar p (\_ -> Done)) (c ())


data Plan :: * where
  Fork :: Plan -> Plan -> Plan
  Done :: Plan
  Get  :: NIVar a -> (a -> Plan) -> Plan
  Put  :: NIVar a -> Process a -> Plan -> Plan
  New  :: NIVarContents a -> (NIVar a -> Plan) -> Plan

-- Note that we cannot convert this plan into usual Functor,
-- Applicative or Monad as the definition of closure is not conducive
-- to define the instance of these type classes

-- Nevertheless we can still use the idea of continuation monad to
-- create a continuation for the plan

-- | Node parallel monad for running tasks on set of nodes
newtype NodePar a = NodePar { runNodePar :: (a -> Plan) -> Plan }


instance Functor NodePar where

  fmap :: (a -> b) -> NodePar a -> NodePar b
  f `fmap` n = NodePar $ \c -> runNodePar n (c . f)

instance Applicative NodePar where

  (<*>) = ap

  pure a = NodePar $ \c -> c a


instance Monad NodePar where

  return = pure

  m >>= k = NodePar $ \c -> runNodePar m $ \a -> runNodePar (k a) c

fire :: NodePar (Process a) -> NodePar (NIVar a)
fire p = do
  i <- new
  fork $ do
    x <- p
    put i x
  return i




  

-- runPar :: NodePar (Block a) -> Process a
-- runPar = 