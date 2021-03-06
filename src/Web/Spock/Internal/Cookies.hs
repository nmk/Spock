{-# LANGUAGE CPP               #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Web.Spock.Internal.Cookies
    ( CookieSettings(..)
    , defaultCookieSettings
    , CookieEOL(..)
    , generateCookieHeaderString
    , parseCookies
    )
where

import qualified Data.ByteString.Char8   as BS
import           Data.Monoid             ((<>))
import qualified Data.Text               as T
import qualified Data.Text.Encoding      as T
import           Data.Time
import qualified Network.HTTP.Types.URI  as URI (urlEncode, urlDecode)
#if MIN_VERSION_time(1,5,0)
#else
import           System.Locale           (defaultTimeLocale)
#endif

-- | Cookie settings
data CookieSettings
   = CookieSettings
   { cs_EOL      :: CookieEOL
     -- ^ cookie expiration setting, see 'CookieEOL'
   , cs_path     :: BS.ByteString
     -- ^ a path for the cookie
   , cs_domain   :: Maybe BS.ByteString
     -- ^ a domain for the cookie. 'Nothing' means no domain is set
   , cs_HTTPOnly :: Bool
     -- ^ whether the cookie should be set as HttpOnly
   , cs_secure   :: Bool
     -- ^ whether the cookie should be marked secure (sent over HTTPS only)
   }

-- | Setting cookie expiration
data CookieEOL
   = CookieValidUntil UTCTime
   -- ^ a point in time in UTC until the cookie is valid
   | CookieValidFor NominalDiffTime
   -- ^ a period (in seconds) for which the cookie is valid
   | CookieValidForSession
   -- ^ the cookie expires with the browser session

-- | Default cookie settings, equals
--
-- > CookieSettings
-- >   { cs_EOL      = CookieValidForSession
-- >   , cs_HTTPOnly = False
-- >   , cs_secure   = False
-- >   , cs_domain   = Nothing
-- >   , cs_path     = "/"
-- >   }
--
defaultCookieSettings :: CookieSettings
defaultCookieSettings =
    CookieSettings
    { cs_EOL      = CookieValidForSession
    , cs_HTTPOnly = False
    , cs_secure   = False
    , cs_domain   = Nothing
    , cs_path     = "/"
    }

generateCookieHeaderString :: T.Text
                           -> T.Text
                           -> CookieSettings
                           -> UTCTime
                           -> BS.ByteString
generateCookieHeaderString name value CookieSettings{..} now =
    BS.intercalate "; " $ filter (not . BS.null) [ nv
                                                 , domain
                                                 , path
                                                 , maxAge
                                                 , expires
                                                 , httpOnly
                                                 , secure
                                                 ]
  where
      nv       = BS.concat [T.encodeUtf8 name, "=", urlEncode value]
      path     = BS.concat ["path=", cs_path]
      domain   = case cs_domain of
                    Nothing -> BS.empty
                    Just d  -> BS.concat ["domain=", d]
      httpOnly = if cs_HTTPOnly then "HttpOnly" else BS.empty
      secure   = if cs_secure then "Secure" else BS.empty

      maxAge = case cs_EOL of
          CookieValidForSession -> BS.empty
          CookieValidFor n      -> "max-age=" <> maxAgeValue n
          CookieValidUntil t    -> "max-age=" <> maxAgeValue (diffUTCTime t now)

      expires = case cs_EOL of
          CookieValidForSession -> BS.empty
          CookieValidFor n      -> "expires=" <> expiresValue (addUTCTime n now)
          CookieValidUntil t    -> "expires=" <> expiresValue t

      maxAgeValue :: NominalDiffTime -> BS.ByteString
      maxAgeValue nrOfSeconds =
          let v = round (max nrOfSeconds 0) :: Integer
          in  BS.pack (show v)

      expiresValue :: UTCTime -> BS.ByteString
      expiresValue t =
          BS.pack $ formatTime defaultTimeLocale "%a, %d %b %Y %X %Z" t

      urlEncode :: T.Text -> BS.ByteString
      urlEncode = URI.urlEncode True . T.encodeUtf8

parseCookies :: BS.ByteString -> [(T.Text, T.Text)]
parseCookies = map parseCookie . BS.split ';'
  where
    parseCookie :: BS.ByteString -> (T.Text, T.Text)
    parseCookie cstr =
        let (name, urlEncValue) = BS.break (== '=') cstr
        in  (T.decodeUtf8 name, T.decodeUtf8 . URI.urlDecode True . BS.drop 1 $ urlEncValue)

