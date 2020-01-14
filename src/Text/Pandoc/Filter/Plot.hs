{-# LANGUAGE MultiWayIf        #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : $header$
Description : Pandoc filter to create figures from code blocks using your plotting toolkit of choice
Copyright   : (c) Laurent P René de Cotret, 2020
License     : GNU GPL, version 2 or above
Maintainer  : laurent.decotret@outlook.com
Stability   : stable
Portability : portable

This module defines a Pandoc filter @makePlot@ and related functions
that can be used to walk over a Pandoc document and generate figures from
a multitude of plotting toolkits.

The syntax for code blocks is simple, Code blocks with the appripriate class
attribute will trigger the filter. For example:

*   @.matplotlib@ for matplotlib-based Python plots;
*   @.plotly_python@ for Plotly-based Python plots;
*   @.matlabplot@ for MATLAB plots;

The code block will be reworked into a script and the output figure will be captured, possible the source code
 used to generate the figure.

Here are the possible attributes what pandoc-plot understands for ALL toolkits:

    * @directory=...@ : Directory where to save the figure.
    * @format=...@: Format of the generated figure. This can be an extension or an acronym, e.g. @format=png@.
    * @caption="..."@: Specify a plot caption (or alternate text). Captions support Markdown formatting and LaTeX math (@$...$@).
    * @dpi=...@: Specify a value for figure resolution, or dots-per-inch. Certain toolkits ignore this.
    * @preamble=...@: Path to a file to include before the code block. Ideal to avoid repetition over many figures.

Default values for the above attributes are stored in the @Configuration@ datatype. These can be specified in a YAML file.
-}
module Text.Pandoc.Filter.Plot (
    -- * Operating on single Pandoc blocks
      makePlot
    , makeMatplotlib
    , makePlotly
    , makeMatlab
    -- * Operating on whole Pandoc documents
    , plotTransform
    ) where

import           Control.Monad.Reader               (runReaderT)

import           Text.Pandoc.Definition
import           Text.Pandoc.Walk                   (walkM)

import           Text.Pandoc.Filter.Plot.Internal

-- | Possible errors returned by the filter
data PandocPlotError
    = ScriptError Int                 -- ^ Running script has yielded an error
    | ScriptChecksFailedError String  -- ^ Script did not pass all checks
    deriving (Eq)

instance Show PandocPlotError where
    show (ScriptError exitcode)        = "Script error: plot could not be generated. Exit code " <> (show exitcode)
    show (ScriptChecksFailedError msg) = "Script did not pass all checks: " <> msg


-- | Highest-level function that can be walked over a Pandoc tree.
-- All code blocks that have the @.plot@ / @.plotly@ class will be considered
-- figures.
makePlot :: Configuration -> Block -> IO Block
makePlot config block =
    compose [ ((makeMatplotlib config) =<<)
            , ((makePlotly     config) =<<)
            , ((makeMatlab     config) =<<) 
            ] 
            (return block)
    where
        compose :: [r -> r] -> r -> r
        compose = flip (foldl (flip id))


-- | Walk over an entire Pandoc document, changing appropriate code blocks
-- into figures. Default configuration is used.
plotTransform :: Configuration -> Pandoc -> IO Pandoc
plotTransform = walkM . makePlot


type Final = Either PandocPlotError Block


-- | Main routine to include plots.
-- Code blocks containing the attributes @.plot@ or @.plotly@ are considered
-- Python plotting scripts. All other possible blocks are ignored.
makePlot' :: RendererM m => Block -> m Final
makePlot' block = do
    parsed <- parseFigureSpec block
    maybe 
        (return $ Right block)
        (\s -> handleResult s <$> runScriptIfNecessary s)
        parsed
    where
        handleResult _ (ScriptChecksFailed msg) = Left  $ ScriptChecksFailedError msg
        handleResult _ (ScriptFailure code)     = Left  $ ScriptError code
        handleResult spec ScriptSuccess         = Right $ toImage spec


makeMatplotlib :: Configuration -> Block -> IO Block
makeMatplotlib config block = 
    runReaderT (unMatplotlibM $ makePlot' block) config
    >>= either (fail . show) return


makePlotly :: Configuration -> Block -> IO Block
makePlotly config block = 
    runReaderT (unPlotlyPythonM $ makePlot' block) config
    >>= either (fail . show) return


makeMatlab :: Configuration -> Block -> IO Block
makeMatlab config block = 
    runReaderT (unMatlabM $ makePlot' block) config
    >>= either (fail . show) return