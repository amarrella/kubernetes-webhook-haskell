{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-|

Module      : Kubernetes.Webhook
Copyright   : (c) Earnest Research, 2020
License     : MIT
Maintainer  : amarrella@earnestresearch.com
Stability   : experimental
Portability : POSIX

This module lets you create [Kubernetes Admission Webhooks](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/).

Example with Servant (note: webhooks in Kubernetes require TLS):

@
  module Kubernetes.Example
      ( startApp,
        app,
      )
    where

  import Control.Monad.IO.Class
  import qualified Data.Aeson as A
  import qualified Data.ByteString as BS
  import qualified Data.HashMap.Strict as HM
  import Data.Text
  import GHC.Generics
  import qualified Kubernetes.Webhook as W
  import Network.Wai
  import Network.Wai.Handler.Warp
  import Network.Wai.Handler.WarpTLS
  import Servant
  import System.Environment

  type API =
    "mutate" :> ReqBody '[JSON] W.AdmissionReviewRequest :> Post '[JSON] W.AdmissionReviewResponse

  data Toleration
    = Toleration
        { effect :: Maybe TolerationEffect,
          key :: Maybe Text,
          operator :: Maybe TolerationOperator,
          tolerationSeconds :: Maybe Integer,
          value :: Maybe Text
        }
    deriving (Generic, A.ToJSON)

  data TolerationEffect = NoSchedule | PreferNoSchedule | NoExecute deriving (Generic, A.ToJSON)

  data TolerationOperator = Exists | Equal deriving (Generic, A.ToJSON)

  testToleration :: Toleration
  testToleration =
    Toleration
      { effect = Just NoSchedule,
        key = Just "dedicated",
        operator = Just Equal,
        tolerationSeconds = Nothing,
        value = Just "test"
      }

  startApp :: IO ()
  startApp = do
    let tlsOpts = tlsSettings "/certs/tls.crt" "/certs/tls.key"
        warpOpts = setPort 8080 defaultSettings
    runTLS tlsOpts warpOpts app

  app :: Application
  app = serve api server

  api :: Proxy API
  api = Proxy

  server :: Server API
  server = mutate

  mutate :: W.AdmissionReviewRequest -> Handler W.AdmissionReviewResponse
  mutate req = pure $ W.mutatingWebhook req (\_ -> Right W.Allowed) addToleration

  addToleration :: W.Patch
  addToleration = 
    W.Patch
      [ W.PatchOperation
          { op = W.Add,
            path = "/spec/tolerations/-",
            from = Nothing,
            value = Just $ A.toJSON testToleration
          }
      ]
@

-}

module Kubernetes.Webhook (
  mutatingWebhook,
  validatingWebhook,
  Allowed(..),
  module Kubernetes.Webhook.Types
) where

import Kubernetes.Webhook.Types
import Data.Either

data Allowed = Allowed

-- | Lets you create a mutating admission webhook 
mutatingWebhook :: AdmissionReviewRequest -- ^ the request the webhook receives from Kubernetes
                -> (AdmissionRequest -> Either Status Allowed) -- ^ logic to validate the request or reject it with an error
                -> Patch -- ^ the change to apply to the object
                -> AdmissionReviewResponse -- ^ the response sent back to Kubernetes
mutatingWebhook AdmissionReviewRequest { request = req } allow patch = 
    admissionReviewResponse AdmissionResponse {
      uid = rid,
      allowed = isRight processedRequest,
      patch = Just patch,
      status = either Just (const Nothing) processedRequest,
      patchType = Just JSONPatch,
      auditAnnotations = Nothing
    }
  where 
    AdmissionRequest { uid = rid } = req 
    processedRequest = allow req

-- | Lets you create a validating admission webhook
validatingWebhook :: AdmissionReviewRequest  -- ^ the request the webhook receives from Kubernetes
                  -> (AdmissionRequest -> Either Status Allowed)  -- ^ logic to validate the request or reject it with an error
                  -> AdmissionReviewResponse -- ^ the response sent back to Kubernetes
validatingWebhook AdmissionReviewRequest { request = req } allow = 
    admissionReviewResponse AdmissionResponse {
      uid = rid,
      allowed = isRight processedRequest,
      patch = Nothing,
      status = either Just (const Nothing) processedRequest,
      patchType = Nothing,
      auditAnnotations = Nothing
    }
  where 
    AdmissionRequest { uid = rid } = req 
    processedRequest = allow req
