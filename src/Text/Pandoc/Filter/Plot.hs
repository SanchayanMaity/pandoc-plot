{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-|
Module      : $header$
Description : Pandoc filter to create figures from code blocks using your plotting toolkit of choice
Copyright   : (c) Laurent P René de Cotret, 2020
License     : GNU GPL, version 2 or above
Maintainer  : laurent.decotret@outlook.com
Stability   : unstable
Portability : portable

This module defines a Pandoc filter @plotTransform@ and related functions
that can be used to walk over a Pandoc document and generate figures from
code blocks, using a multitude of plotting toolkits.

The syntax for code blocks is simple. Code blocks with the appropriate class
attribute will trigger the filter:

*   @matplotlib@ for matplotlib-based Python plots;
*   @plotly_python@ for Plotly-based Python plots;
*   @matlabplot@ for MATLAB plots;
*   @mathplot@ for Mathematica plots;
*   @octaveplot@ for GNU Octave plots;
*   @ggplot2@ for ggplot2-based R plots;
*   @gnuplot@ for gnuplot plots;

For example, in Markdown:

@
    This is a paragraph.

    ```{.matlabplot}
    figure()
    plot([1,2,3,4,5], [1,2,3,4,5], '-k)
    ```
@

The code block will be reworked into a script and the output figure will be captured. Optionally, the source code
 used to generate the figure will be linked in the caption.

Here are the possible attributes what pandoc-plot understands for ALL toolkits:

    * @directory=...@ : Directory where to save the figure.
    * @source=true|false@ : Whether or not to link the source code of this figure in the caption. Ideal for web pages, for example. Default is false.
    * @format=...@: Format of the generated figure. This can be an extension or an acronym, e.g. @format=PNG@.
    * @caption="..."@: Specify a plot caption (or alternate text). Format for captions is specified in the documentation for the @Configuration@ type.
    * @dpi=...@: Specify a value for figure resolution, or dots-per-inch. Certain toolkits ignore this.
    * @preamble=...@: Path to a file to include before the code block. Ideal to avoid repetition over many figures.

Default values for the above attributes are stored in the @Configuration@ datatype. These can be specified in a 
YAML file which must be named ".pandoc-plot.yml".

Here is an example code block which will render a figure using gnuplot, in Markdown:

@
    ```{.gnuplot format=png caption="Sinusoidal function" source=true}
    sin(x)

    set xlabel "x"
    set ylabel "y"
    ```
@
-}
module Text.Pandoc.Filter.Plot (
    -- * Operating on single Pandoc blocks
      makePlot
    -- * Operating on whole Pandoc documents
    , plotTransform
    -- * Cleaning output directories
    , cleanOutputDirs
    -- * Runtime configuration
    , configuration
    , defaultConfiguration
    , Configuration(..)
    , SaveFormat(..)
    , Script
    -- * For testing and internal purposes ONLY
    , make
    , make'
    , PandocPlotError(..)
    , readDoc
    , availableToolkits
    , unavailableToolkits
    ) where

import Control.Concurrent                   (getNumCapabilities)
import Control.Concurrent.ParallelIO.Local  (withPool, parallel)

import Control.Monad.Reader                 (runReaderT)

import System.IO                            (hPutStrLn, stderr)

import Text.Pandoc.Definition
import Text.Pandoc.Walk                     (walkM)

import Text.Pandoc.Filter.Plot.Internal


-- | Highest-level function that can be walked over a Pandoc tree.
-- All code blocks that have the appropriate class names will be considered
-- figures, e.g. @.matplotlib@.
--
-- Failing to render a figure does not stop the filter, so that you may run the filter
-- on documents without having all necessary toolkits installed. In this case, error
-- messages are printed to stderr, and blocks are left unchanged.
makePlot :: Configuration -- ^ Configuration for default values
         -> Block 
         -> IO Block
makePlot conf block = maybe (return block) (\tk -> make tk conf block) (plotToolkit block)


-- | Walk over an entire Pandoc document, transforming appropriate code blocks
-- into figures. 
--
-- Based on configuration, this function might operate on blocks in parallel.
--
-- Failing to render a figure does not stop the filter, so that you may run the filter
-- on documents without having all necessary toolkits installed. In this case, error
-- messages are printed to stderr, and blocks are left unchanged.
plotTransform :: Configuration -- ^ Configuration for default values
              -> Pandoc        -- ^ Input document
              -> IO Pandoc
plotTransform conf = walkFunc (makePlot conf)
    where
        walkFunc = if allowParallel conf then parWalkM else walkM


-- | Walk over pandoc document, potentially in parallel.
-- This function is equivalent to walkM for single-threaded operation
parWalkM :: (Block -> IO Block) -> Pandoc -> IO Pandoc
parWalkM f doc@(Pandoc meta blocks) = do
    availableThreads <- getNumCapabilities
    let numThreads = min availableThreads (length blocks)
    if numThreads == 1
        then walkM f doc
        else withPool numThreads $ \pool -> parallel pool (f <$> blocks)
            >>= \newBlocks -> return $ Pandoc meta newBlocks


-- | Force to use a particular toolkit to render appropriate code blocks.
--
-- Failing to render a figure does not stop the filter, so that you may run the filter
-- on documents without having all necessary toolkits installed. In this case, error
-- messages are printed to stderr, and blocks are left unchanged.
make :: Toolkit       -- ^ Plotting toolkit.
     -> Configuration -- ^ Configuration for default values.
     -> Block 
     -> IO Block
make tk conf blk = 
    either (const (return blk) . showErr) return =<< make' tk conf blk
    where
        showErr e = hPutStrLn stderr $ show e


make' :: Toolkit 
      -> Configuration 
      -> Block 
      -> IO (Either PandocPlotError Block)
make' tk conf block = runReaderT (make'' block) (PlotEnv tk conf)
    where
        make'' :: Block -> PlotM (Either PandocPlotError Block)
        make'' blk = parseFigureSpec blk
                    >>= maybe
                        (return $ Right blk)
                        (\s -> runScriptIfNecessary s >>= handleResult s)
            where
                handleResult spec ScriptSuccess          = return $ Right $ toImage (captionFormat conf) spec
                handleResult _ (ScriptFailure msg code)  = return $ Left (ScriptRuntimeError msg code) 
                handleResult _ (ScriptChecksFailed msg)  = return $ Left (ScriptChecksFailedError msg)
                handleResult _ (ToolkitNotInstalled tk') = return $ Left (ToolkitNotInstalledError tk') 


data PandocPlotError
    = ScriptRuntimeError String Int
    | ScriptChecksFailedError String
    | ToolkitNotInstalledError Toolkit

instance Show PandocPlotError where
    show (ScriptRuntimeError _ exitcode) = "ERROR (pandoc-plot) The script failed with exit code " <> show exitcode <> "."
    show (ScriptChecksFailedError msg)   = "ERROR (pandoc-plot) A script check failed with message: " <> msg <> "."
    show (ToolkitNotInstalledError tk)   = "ERROR (pandoc-plot) The " <> show tk <> " toolkit is required but not installed."