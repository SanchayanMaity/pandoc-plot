{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}


{-|
Module      : $header$
Copyright   : (c) Laurent P René de Cotret, 2020
License     : GNU GPL, version 2 or above
Maintainer  : laurent.decotret@outlook.com
Stability   : internal
Portability : portable

Reading configuration from file
-}

module Text.Pandoc.Filter.Plot.Configuration (
      configuration
    , configurationPathMeta
    , defaultConfiguration
) where

import           Data.Default.Class     (Default, def)
import           Data.Maybe             (fromMaybe)
import           Data.Text              (Text, pack, unpack)
import qualified Data.Text.IO           as TIO
import           Data.Yaml
import           Data.Yaml.Config       (ignoreEnv, loadYamlSettings)

import           Text.Pandoc.Definition (Format(..), Pandoc(..), MetaValue(..), lookupMeta)

import Text.Pandoc.Filter.Plot.Types
import Text.Pandoc.Filter.Plot.Logging  (Verbosity(..), LogSink(..))

-- | Read configuration from a YAML file. The
-- keys are exactly the same as for code blocks.
--
-- If a key is not present, its value will be set
-- to the default value. Parsing errors result in thrown exceptions.
configuration :: FilePath -> IO Configuration
configuration fp = (loadYamlSettings [fp] [] ignoreEnv) >>= renderConfig


-- | Default configuration values.
--
-- @since 0.5.0.0
defaultConfiguration :: Configuration
defaultConfiguration = def


-- | Extact path to configuration from the metadata in a Pandoc document.
-- The path to the configuration file should be under the @plot-configuration@ key.
-- In case there is no such metadata, return the default configuration.
--
-- For example, at the top of a markdown file:
--
-- @
--     ---
--     title: My document
--     author: John Doe
--     plot-configuration: /path/to/file.yml
--     ---     
-- @
--
-- The same can be specified via the command line using Pandoc's @-M@ flag:
--
-- > pandoc --filter pandoc-plot -M plot-configuration="path/to/file.yml" ...
--
-- @since 0.6.0.0
configurationPathMeta :: Pandoc -> Maybe FilePath
configurationPathMeta (Pandoc meta _) = 
        lookupMeta "plot-configuration" meta >>= getPath
    where
        getPath (MetaString s) = Just (unpack s)
        getPath _              = Nothing


-- We define a precursor type because preambles are best specified as file paths,
-- but we want to read those files before building a full
-- @Configuration@ value.
data ConfigPrecursor = ConfigPrecursor
    { _defaultDirectory  :: !FilePath    -- ^ The default directory where figures will be saved.
    , _defaultWithSource :: !Bool        -- ^ The default behavior of whether or not to include links to source code and high-res
    , _defaultDPI        :: !Int         -- ^ The default dots-per-inch value for generated figures. Renderers might ignore this.
    , _defaultSaveFormat :: !SaveFormat  -- ^ The default save format of generated figures.
    , _captionFormat     :: !Format      -- ^ Caption format in Pandoc notation, e.g. "markdown+tex_math_dollars".
    
    , _logPrec           :: !LoggingPrecursor

    , _matplotlibPrec    :: !MatplotlibPrecursor
    , _matlabPrec        :: !MatlabPrecursor
    , _plotlyPythonPrec  :: !PlotlyPythonPrecursor
    , _plotlyRPrec       :: !PlotlyRPrecursor
    , _mathematicaPrec   :: !MathematicaPrecursor
    , _octavePrec        :: !OctavePrecursor
    , _ggplot2Prec       :: !GGPlot2Precursor
    , _gnuplotPrec       :: !GNUPlotPrecursor
    , _graphvizPrec      :: !GraphvizPrecursor
    }

instance Default ConfigPrecursor where
    def = ConfigPrecursor
        { _defaultDirectory  = defaultDirectory def
        , _defaultWithSource = defaultWithSource def
        , _defaultDPI        = defaultDPI def
        , _defaultSaveFormat = defaultSaveFormat def
        , _captionFormat     = captionFormat def

        , _logPrec             = def
        
        , _matplotlibPrec    = def
        , _matlabPrec        = def
        , _plotlyPythonPrec  = def
        , _plotlyRPrec       = def
        , _mathematicaPrec   = def
        , _octavePrec        = def
        , _ggplot2Prec       = def
        , _gnuplotPrec       = def
        , _graphvizPrec      = def
        }


data LoggingPrecursor = LoggingPrecursor { _logVerbosity :: !Verbosity
                                         , _logFilePath  :: !(Maybe FilePath)
                                         }

-- Separate YAML clauses have their own types.
data MatplotlibPrecursor = MatplotlibPrecursor
        { _matplotlibPreamble    :: !(Maybe FilePath)
        , _matplotlibTightBBox   :: !Bool
        , _matplotlibTransparent :: !Bool
        , _matplotlibExe         :: !FilePath
        }
data MatlabPrecursor        = MatlabPrecursor       {_matlabPreamble       :: !(Maybe FilePath), _matlabExe       :: !FilePath}
data PlotlyPythonPrecursor  = PlotlyPythonPrecursor {_plotlyPythonPreamble :: !(Maybe FilePath), _plotlyPythonExe :: !FilePath}
data PlotlyRPrecursor       = PlotlyRPrecursor      {_plotlyRPreamble      :: !(Maybe FilePath), _plotlyRExe      :: !FilePath}
data MathematicaPrecursor   = MathematicaPrecursor  {_mathematicaPreamble  :: !(Maybe FilePath), _mathematicaExe  :: !FilePath}
data OctavePrecursor        = OctavePrecursor       {_octavePreamble       :: !(Maybe FilePath), _octaveExe       :: !FilePath}
data GGPlot2Precursor       = GGPlot2Precursor      {_ggplot2Preamble      :: !(Maybe FilePath), _ggplot2Exe      :: !FilePath}
data GNUPlotPrecursor       = GNUPlotPrecursor      {_gnuplotPreamble      :: !(Maybe FilePath), _gnuplotExe      :: !FilePath}
data GraphvizPrecursor      = GraphvizPrecursor     {_graphvizPreamble     :: !(Maybe FilePath), _graphvizExe    :: !FilePath}

instance Default LoggingPrecursor where
    def = LoggingPrecursor (logVerbosity def) Nothing -- _logFilePath=Nothing implies log to stderr

instance Default MatplotlibPrecursor where
    def = MatplotlibPrecursor Nothing (matplotlibTightBBox def) (matplotlibTransparent def) (matplotlibExe def)

instance Default MatlabPrecursor        where def = MatlabPrecursor       Nothing (matlabExe def)
instance Default PlotlyPythonPrecursor  where def = PlotlyPythonPrecursor Nothing (plotlyPythonExe def)
instance Default PlotlyRPrecursor       where def = PlotlyRPrecursor      Nothing (plotlyRExe def)
instance Default MathematicaPrecursor   where def = MathematicaPrecursor  Nothing (mathematicaExe def)
instance Default OctavePrecursor        where def = OctavePrecursor       Nothing (octaveExe def)
instance Default GGPlot2Precursor       where def = GGPlot2Precursor      Nothing (ggplot2Exe def)
instance Default GNUPlotPrecursor       where def = GNUPlotPrecursor      Nothing (gnuplotExe def)
instance Default GraphvizPrecursor      where def = GraphvizPrecursor     Nothing (graphvizExe def)


instance FromJSON LoggingPrecursor where
    parseJSON (Object v) = 
        LoggingPrecursor <$> v .:? "verbosity" .!= (logVerbosity def)
                         <*> v .:? "filepath"
    parseJSON _ = fail $ mconcat ["Could not parse logging configuration. "]

instance FromJSON MatplotlibPrecursor where
    parseJSON (Object v) = 
        MatplotlibPrecursor
            <$> v .:? (tshow PreambleK)
            <*> v .:? (tshow MatplotlibTightBBoxK)   .!= (matplotlibTightBBox def) 
            <*> v .:? (tshow MatplotlibTransparentK) .!= (matplotlibTransparent def)
            <*> v .:? (tshow ExecutableK)  .!= (matplotlibExe def)
    parseJSON _ = fail $ mconcat ["Could not parse ", show Matplotlib, " configuration."]

instance FromJSON MatlabPrecursor where
    parseJSON (Object v) = MatlabPrecursor <$> v .:? (tshow PreambleK) <*> v .:? (tshow ExecutableK) .!= (matlabExe def)
    parseJSON _ = fail $ mconcat ["Could not parse ", show Matlab, " configuration."]

instance FromJSON PlotlyPythonPrecursor where
    parseJSON (Object v) = PlotlyPythonPrecursor <$> v .:? (tshow PreambleK) <*> v .:? (tshow ExecutableK) .!= (plotlyPythonExe def)
    parseJSON _ = fail $ mconcat ["Could not parse ", show PlotlyPython, " configuration."]

instance FromJSON PlotlyRPrecursor where
    parseJSON (Object v) = PlotlyRPrecursor <$> v .:? (tshow PreambleK) <*> v .:? (tshow ExecutableK) .!= (plotlyRExe def)
    parseJSON _ = fail $ mconcat ["Could not parse ", show PlotlyR, " configuration."]

instance FromJSON MathematicaPrecursor where
    parseJSON (Object v) = MathematicaPrecursor <$> v .:? (tshow PreambleK) <*> v .:? (tshow ExecutableK) .!= (mathematicaExe def)
    parseJSON _ = fail $ mconcat ["Could not parse ", show Mathematica, " configuration."]

instance FromJSON OctavePrecursor where
    parseJSON (Object v) = OctavePrecursor <$> v .:? (tshow PreambleK) <*> v .:? (tshow ExecutableK) .!= (octaveExe def)
    parseJSON _ = fail $ mconcat ["Could not parse ", show Octave, " configuration."]

instance FromJSON GGPlot2Precursor where
    parseJSON (Object v) = GGPlot2Precursor <$> v .:? (tshow PreambleK) <*> v .:? (tshow ExecutableK) .!= (ggplot2Exe def)
    parseJSON _ = fail $ mconcat ["Could not parse ", show GGPlot2, " configuration."]

instance FromJSON GNUPlotPrecursor where
    parseJSON (Object v) = GNUPlotPrecursor <$> v .:? (tshow PreambleK) <*> v .:? (tshow ExecutableK) .!= (gnuplotExe def)
    parseJSON _ = fail $ mconcat ["Could not parse ", show GNUPlot, " configuration."]

instance FromJSON GraphvizPrecursor where
    parseJSON (Object v) = GraphvizPrecursor <$> v .:? (tshow PreambleK) <*> v .:? (tshow ExecutableK) .!= (graphvizExe def)
    parseJSON _ = fail $ mconcat ["Could not parse ", show Graphviz, " configuration."]


instance FromJSON ConfigPrecursor where
    parseJSON (Null) = return def -- In case of empty file
    parseJSON (Object v) = do
        
        _defaultDirectory  <- v .:? (tshow DirectoryK)     .!= (_defaultDirectory def)
        _defaultWithSource <- v .:? (tshow WithSourceK)    .!= (_defaultWithSource def)
        _defaultDPI        <- v .:? (tshow DpiK)           .!= (_defaultDPI def)
        _defaultSaveFormat <- v .:? (tshow SaveFormatK)    .!= (_defaultSaveFormat def)
        _captionFormat     <- v .:? (tshow CaptionFormatK) .!= (_captionFormat def)

        _logPrec           <- v .:? "logging"              .!= def

        _matplotlibPrec    <- v .:? (cls Matplotlib)       .!= def
        _matlabPrec        <- v .:? (cls Matlab)           .!= def
        _plotlyPythonPrec  <- v .:? (cls PlotlyPython)     .!= def
        _plotlyRPrec       <- v .:? (cls PlotlyR)          .!= def
        _mathematicaPrec   <- v .:? (cls Mathematica)      .!= def
        _octavePrec        <- v .:? (cls Octave)           .!= def
        _ggplot2Prec       <- v .:? (cls GGPlot2)          .!= def
        _gnuplotPrec       <- v .:? (cls GNUPlot)          .!= def
        _graphvizPrec      <- v .:? (cls Graphviz)         .!= def

        return $ ConfigPrecursor{..}
    parseJSON _          = fail "Could not parse configuration."


renderConfig :: ConfigPrecursor -> IO Configuration
renderConfig ConfigPrecursor{..} = do
    let defaultDirectory  = _defaultDirectory
        defaultWithSource = _defaultWithSource
        defaultDPI        = _defaultDPI
        defaultSaveFormat = _defaultSaveFormat
        captionFormat     = _captionFormat

        logVerbosity = _logVerbosity _logPrec
        logSink      = maybe StdErr LogFile (_logFilePath _logPrec)

        matplotlibTightBBox   = _matplotlibTightBBox _matplotlibPrec
        matplotlibTransparent = _matplotlibTransparent _matplotlibPrec

        matplotlibExe   = _matplotlibExe _matplotlibPrec
        matlabExe       = _matlabExe _matlabPrec
        plotlyPythonExe = _plotlyPythonExe _plotlyPythonPrec
        plotlyRExe      = _plotlyRExe _plotlyRPrec
        mathematicaExe  = _mathematicaExe _mathematicaPrec
        octaveExe       = _octaveExe _octavePrec
        ggplot2Exe      = _ggplot2Exe _ggplot2Prec
        gnuplotExe      = _gnuplotExe _gnuplotPrec
        graphvizExe     = _graphvizExe _graphvizPrec
    
    matplotlibPreamble   <- readPreamble (_matplotlibPreamble _matplotlibPrec)
    matlabPreamble       <- readPreamble (_matlabPreamble _matlabPrec)
    plotlyPythonPreamble <- readPreamble (_plotlyPythonPreamble _plotlyPythonPrec)
    plotlyRPreamble      <- readPreamble (_plotlyRPreamble _plotlyRPrec)
    mathematicaPreamble  <- readPreamble (_mathematicaPreamble _mathematicaPrec)
    octavePreamble       <- readPreamble (_octavePreamble _octavePrec)
    ggplot2Preamble      <- readPreamble (_ggplot2Preamble _ggplot2Prec)
    gnuplotPreamble      <- readPreamble (_gnuplotPreamble _gnuplotPrec)
    graphvizPreamble     <- readPreamble (_graphvizPreamble _graphvizPrec)

    return Configuration{..}
    where
        readPreamble fp = fromMaybe mempty $ TIO.readFile <$> fp


tshow :: Show a => a -> Text
tshow = pack . show