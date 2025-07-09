#!/usr/bin/env python3

"""
AI-based Git Merge Driver.

This script is a Git merge driver that uses AI to resolve merge conflicts
if git's default merge strategy fails.

It supports both Anthropic (Claude) and Google (Gemini) AI APIs.
"""

import argparse
import logging
import os
import sys
import subprocess
import shutil
from enum import Enum

# AI API libraries
try:
    import anthropic
    ANTHROPIC_AVAILABLE = True
except ImportError:
    ANTHROPIC_AVAILABLE = False

try:
    import google.generativeai as genai
    from google.generativeai.protos import Candidate
    GOOGLE_AVAILABLE = True
except ImportError:
    GOOGLE_AVAILABLE = False

logger = None

# Used for updating the merge commit message using the ark-md prepare_commit_msg git hook
AI_RESOLUTIONS_FILE = "/tmp/ark-md-ai-resolutions"

# Configure logging
class ColorLogFormatter(logging.Formatter):
    """Custom formatter to add colors to log messages"""
    
    # Color codes
    COLORS = {
        'DEBUG': '\033[0;36m',     # Cyan
        'INFO': '\033[0;32m',      # Green  
        'WARNING': '\033[1;33m',   # Yellow
        'ERROR': '\033[0;31m',     # Red
        'CRITICAL': '\033[0;35m',  # Magenta
    }
    RESET = '\033[0m'
    
    def format(self, record):
        # Add color based on log level
        color = self.COLORS.get(record.levelname, self.RESET)
        record.levelname = f"{color}[ARK-MD]{self.RESET}"
        return super().format(record)


class PlainLogFormatter(logging.Formatter):
    """Custom formatter without colors"""
    
    def format(self, record):
        record.levelname = f"[ARK-MD] {record.levelname}:"
        return super().format(record)


def setup_logging(use_colors=False):
    """Setup logging with optional colors"""
    logger = logging.getLogger('ark-md')
    
    # Clear any existing handlers
    logger.handlers.clear()
    
    logger.setLevel(logging.INFO)
    
    # Create handler that outputs to stderr
    handler = logging.StreamHandler(sys.stderr)
    handler.setLevel(logging.INFO)
    
    # Create formatter based on color preference
    if use_colors:
        formatter = ColorLogFormatter('%(levelname)s %(message)s')
    else:
        formatter = PlainLogFormatter('%(levelname)s %(message)s')
    
    handler.setFormatter(formatter)
    
    # Add handler to logger
    logger.addHandler(handler)
    
    return logger


# AI API providers
class AIProviderName(Enum):
    ANTHROPIC = "Anthropic"
    GOOGLE = "Google"
    GOOGLE_CLOUD = "Google Cloud"


class AIProvider:
    def __init__(self, api_key, model, max_tokens, temperature):
        self.api_key = api_key
        self.model = model
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.provider_name: AIProviderName = None
        # This is used only for an informational warning. The providers have large context windows.
        self.max_input_tokens = 200000

    def __str__(self):
        return f"{self.provider_name.value} ({self.model})" if self.provider_name else "Undefined"

    def generate_content(self, prompt) -> tuple[str, str]:
        """Generic wrapper for generating content using the AI API.
        The subclass may use "generate content" or stream content or whatever
        is appropriate for that provider.
        
        Returns:
            tuple[str, str]: The resolved content and the stop reason
        """
        raise NotImplementedError("Subclasses must implement this method")


class AnthropicProvider(AIProvider):
    def __init__(self, api_key, model, max_tokens, temperature):
        super().__init__(api_key, model, max_tokens, temperature)
        self.provider_name = AIProviderName.ANTHROPIC

    def generate_content(self, prompt) -> tuple[str, str]:
        client = anthropic.Anthropic(api_key=self.api_key)
        
        # Use streaming for large requests
        stream = client.messages.create(
            model=self.model,
            max_tokens=self.max_tokens,
            temperature=self.temperature,
            messages=[{"role": "user", "content": prompt}],
            stream=True
        )
        
        resolved_content = ""
        stop_reason = None
        
        # Collect streamed content
        for chunk in stream:
            logger.debug(f"{self.provider_name.value} streaming chunk: {chunk}")
            if chunk.type == "content_block_delta":
                if hasattr(chunk.delta, 'text'):
                    resolved_content += chunk.delta.text
            elif chunk.type == "message_stop":
                stop_reason = chunk.stop_reason if hasattr(chunk, 'stop_reason') else "end_turn"
        
        # MAX_TOKENS is the only stop condition we care about for now
        stop_reason = stop_reason.upper() if stop_reason else "END_TURN"
        if stop_reason == "MAX_TOKENS":
            logger.warning("Response blocked due to max tokens")
        
        return resolved_content, stop_reason


class GoogleProvider(AIProvider):
    def __init__(self, api_key, model, max_tokens, temperature):
        super().__init__(api_key, model, max_tokens, temperature)
        self.provider_name = AIProviderName.GOOGLE
    
    def generate_content(self, prompt):
        genai.configure(api_key=self.api_key)
        model = genai.GenerativeModel(self.model)
        response = model.generate_content(
            prompt,
            generation_config={
                'temperature': self.temperature,
                'max_output_tokens': self.max_tokens
            }
        )
        
        logger.debug(f"{self.provider_name.value} response: {response}")
        
        # Get the response text
        if response.text:
            resolved_content = response.text
        elif response.candidates:
            # Try to get text from first candidate
            candidate = response.candidates[0]
            if candidate.content and candidate.content.parts:
                resolved_content = candidate.content.parts[0].text
            else:
                resolved_content = str(candidate)
        else:
            logger.error("Could not extract text from response")
            resolved_content = None
        
        # Get the stop reason
        if response.candidates:
            candidate = response.candidates[0]
            if candidate.finish_reason:
                if candidate.finish_reason == Candidate.FinishReason.MAX_TOKENS:
                    logger.warning("Response blocked due to max tokens")
                    stop_reason = Candidate.FinishReason.MAX_TOKENS.name
                else:
                    stop_reason = str(candidate.finish_reason).upper()
        else:
            stop_reason = Candidate.FinishReason.FINISH_REASON_UNSPECIFIED.name
        
        return resolved_content, stop_reason


# Factory function to get the AI provider based on the name
def create_ai_provider(provider: AIProviderName, api_key, model, max_tokens, temperature):
    if provider == AIProviderName.GOOGLE:
        return GoogleProvider(api_key, model, max_tokens, temperature)
    elif provider == AIProviderName.ANTHROPIC:
        return AnthropicProvider(api_key, model, max_tokens, temperature)
    else:
        return None


def estimate_tokens(text):
    """Very rough estimation: ~4 characters per token on average"""
    return len(text) // 4


def write_file_content(file_path: str, content: str) -> bool:
    """Write content to a file."""
    try:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        return True
    except IOError as e:
        logger.error(f"Error writing file {file_path}: {e}")
        return False


def run_git_merge_file(ancestor_file: str, current_file: str, other_file: str, 
                         conflict_marker_size: int = 7, file_path: str = None,
                         artifacts: bool = False, write_conflict: bool = False,
                         diff_algorithm: str = "myers") -> bool:
    """
    Attempt to merge using git's default merge algorithm.
    
    Args:
        ancestor_file: Path to the ancestor (base) file
        current_file: Path to the current (ours) file  
        other_file: Path to the other (theirs) file
        conflict_marker_size: Size of conflict markers
        file_path: Path to the file being merged
    Returns:
        True if merge was successful (no conflicts), False otherwise
    """
    # Define whether git should handle writing out the merge conflict as it
    # would normally or if we'll handle it ourselves. If we're not using AI,
    # then --no-stdout will cause git to write the conflict rather than
    # sending it to stdout for us to handle.
    output = "--stdout" if not write_conflict else "--no-stdout"
    
    try:
        # Use git merge-file to attempt default merge
        cmd = [
            "git", "merge-file", output,
            f"--diff-algorithm={diff_algorithm}",
            f"--marker-size={conflict_marker_size}",
            current_file,
            ancestor_file, 
            other_file
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        # git merge-file returns:
        # 0 = clean merge
        # 1 = conflicts found
        # >1 = error
        if result.returncode == 0:
            logger.debug(f"Merge successful using diff algorithm: {diff_algorithm}.")
            write_file_content(current_file, result.stdout)
            return True
        elif result.returncode == 1:
            logger.debug(f"Conflicts found in: {file_path}. Using diff algorithm: {diff_algorithm}.")
            # no need to save the conflict since git will do it for us
            if artifacts and not write_conflict:
                conflict_file = f"{file_path}.{diff_algorithm}.conflict"
                with open(conflict_file, 'w') as file:
                    file.write(result.stdout)
                    logger.info(f"Conflict saved to: {conflict_file}")
            return False
        else:
            logger.error(f"Error ({result.returncode}) running git merge-file: {result.stdout} {result.stderr}")
            return False
            
    except subprocess.SubprocessError as e:
        logger.error(f"Failed to run git merge-file: {e}")
        return False


def record_ai_resolution(file_path):
    """Record a successful AI resolution"""
    with open(AI_RESOLUTIONS_FILE, "a") as f:
        f.write(f"{file_path}\n")
    logger.debug(f"Recorded AI resolution for: {file_path}")


def build_apply_diff_prompt(source_code, diff, file_path):
    """Build a prompt to resolve the conflict by applying a diff to the
    provided file. This approach is used for both rebase and merge conflicts
    where the conflict is due to Red Hat changes.
    This will not resolve conflicts due to missing commits from upstream.
    """
    
    prompt = f"""You are an expert Linux kernel developer and you are asked to apply changes to a file.

**TASK:** 
Apply the changes shown in the file diff to the upstream file: {file_path}

**CRITICAL RULES:**
1. Start with the upstream file exactly as it is provided
2. Apply ONLY the changes shown in the file diff
3. DO NOT be creative or make improvements

**INSTRUCTIONS:**
1. Take the upstream file as your starting point
2. Apply the changes shown in the file diff:
   - Lines starting with '+' should be added
   - Lines starting with '-' should be removed
   - Pay attention to line numbers and context
   - DO NOT add or remove lines that are not prefixed with '+' or '-' in the file diff
3. The result should be the upstream file with the changes applied

**EXAMPLE:**
For example, in the following diff, you would add the line "new_code();" and remove the line "old_code();".
```
@@ -10,6 +10,9 @@
 void function() {{
-    old_code();
     existing_code();
+    new_code();
 }}
```

**VERIFICATION:**
- Every line in your result should come from either the upstream file or the lines beginning with '+' in the file diff
- The only lines that can be removed are the ones beginning with '-' in the file diff
- The result should be the upstream file with the file diff changes applied

**OUTPUT:**
 - Provide only the final file content.
 - DO NOT include any explanations
 - DO NOT include any markdown formatting
 - DO NOT include any conflict markers
 
**UPSTREAM FILE (your starting point):**
```
{source_code}
```

**FILE DIFF (the changes to be applied):**
```
{diff}
```
"""
    return prompt


def get_file_diff(base_file, ours_file, file_path):
    """Get the diff between two files and fix up the diff to be relative to the file_path"""
    file_diff = None
    try:
        result = subprocess.run(f"git diff --no-index {base_file} {ours_file}", 
                                shell=True, capture_output=True, text=True)
        # Git diff returns 0 if no differences, 1 if differences, >1 for errors
        if result.returncode == 1:
            # Fix up the diff, replace the base_file name and ours_file name with the real file name
            file_diff = result.stdout.strip()
            file_diff = file_diff.replace(base_file, file_path)
            file_diff = file_diff.replace(ours_file, file_path)            
    except Exception as e:
        logger.error(f"Failed to get file diff for {file_path}: {e}")
        file_diff = None
    
    return file_diff


def get_ai_provider() -> AIProvider:
    """Get the AI provider based on the available API keys"""
    anthropic_key = os.getenv('ANTHROPIC_API_KEY')
    gemini_key = os.getenv('GOOGLE_GEMINI_API_KEY')
    
    if anthropic_key and gemini_key:
        logger.warning("Both ANTHROPIC_API_KEY and GOOGLE_GEMINI_API_KEY are set. Using Gemini.")
    
    if gemini_key and GOOGLE_AVAILABLE:
        ai_provider = create_ai_provider(AIProviderName.GOOGLE, gemini_key, "gemini-2.5-pro", 65536, 0.2)
    elif anthropic_key and ANTHROPIC_AVAILABLE:
        ai_provider = create_ai_provider(AIProviderName.ANTHROPIC, anthropic_key, "claude-sonnet-4-20250514", 45000, 0.1)
    else:
        ai_provider = None
    
    if ai_provider is None:
        if not anthropic_key and not gemini_key:
            logger.error("Please set either the ANTHROPIC_API_KEY or GOOGLE_GEMINI_API_KEY environment variable")
        else:
            if anthropic_key and not ANTHROPIC_AVAILABLE:
                logger.error("anthropic library not installed. Run: pip install anthropic")
            if gemini_key and not GOOGLE_AVAILABLE:
                logger.error("google-generativeai library not installed. Run: pip install google-generativeai")
    
    return ai_provider


def resolve_with_ai(ai_provider, ancestor_file, current_file, other_file,
                    file_path, reflog_action, mode):
    """Resolve conflict with AI"""
    
    logger.info(f"Built-in strategies failed. Calling {ai_provider} to resolve the conflict.")
    
    try:
        # Get the changes that need to be applied
        file_diff = ""
        
        # In kernel-ark, conflicts are due to Red Hat changes and that's what
        # we want to identify in our git diff. If this is a backport (cherry-pick)
        # then the conflict is likely due to missing commits from upstream.
        # In that case, we will likely need a different strategy to resolve the
        # conflict and this is not currently supported.
        if reflog_action == "rebase":
            ours_file = other_file # os-build's version
            theirs_file = current_file # upstream's version
            base_file = ancestor_file
        else: # merge - the normal usage of ours/theirs/base
            ours_file = current_file # os-build's version
            theirs_file = other_file # upstream's version
            base_file = ancestor_file
        
        file_diff = get_file_diff(base_file, ours_file, file_path)
        if file_diff is None:
            return False
        
        # Get the file content
        source_code = ""
        if os.path.exists(theirs_file) and os.path.getsize(theirs_file) > 0:
            with open(theirs_file, 'r', encoding='utf-8', errors='ignore') as f:
                source_code = f.read()
        
        # Prepare the prompt focused on applying a specific diff
        prompt = build_apply_diff_prompt(source_code, file_diff, file_path)
        
        logger.debug(f"Prompt: {prompt}")

        # Estimate token usage
        estimated_input_tokens = estimate_tokens(prompt)
        estimated_output_tokens = estimate_tokens(source_code)
        
        # This is only an informational warning.
        if estimated_input_tokens > ai_provider.max_input_tokens:
            logger.warning(f"Very large input (~{estimated_input_tokens} tokens). This may exceed API limits.")
        
        # If we see this warning, then we will likely see the request fail.
        if estimated_output_tokens > ai_provider.max_tokens:
            logger.warning(f"Large expected output (~{estimated_output_tokens} tokens). This may exceed max_tokens limit ({ai_provider.max_tokens}).")
        
        # Make AI API call    
        try:
            resolved_content, stop_reason = ai_provider.generate_content(prompt)
        except Exception as e:
            # from anthropic I've seen overloaded and server error as stop reasons
            logger.error(f"AI API error: {e}")
            return False
        
        if not resolved_content:
            logger.error(f"Failed to extract resolved content from response: {stop_reason}")
            return False
        
        # Check if the response was truncated due to max_tokens
        if stop_reason == "MAX_TOKENS":
            logger.warning("Response was truncated due to token limit. The resolved file may be incomplete.")
            return False
        
        # Sadly, the model may return the file in markdown code blocks so we need to remove them.
        resolved_content = resolved_content.strip()
        lines = resolved_content.splitlines()
        if lines[0].startswith('```'):
            lines = lines[1:]
        if lines[-1].endswith('```'):
            lines[-1] = lines[-1].rstrip('`')
        resolved_content = '\n'.join(lines)
        # Add a newline to the end of the file if it doesn't have one
        if not resolved_content.endswith('\n'):
            resolved_content += '\n'
        
        if mode == "driver":
            # Write the resolved content to the current file. Do not use the file_path or it won't be committed
            write_file_content(current_file, resolved_content)
        else:
            # mergetool expects the resolved content to be written to the file_path
            write_file_content(file_path, resolved_content)
        
        logger.info(f"Successfully resolved merge conflict")
        record_ai_resolution(file_path)
        return True
    
    except Exception as e:
        logger.error(f"Failed to resolve merge conflict with {ai_provider}: {e}")
        return False


def copy_file(src_path: str, extension: str = ""):
    """
    Make a copy of a file.
    """
    dst_path = f"{src_path}.{extension}"
    logger.info(f"Saved: {dst_path}")
    shutil.copy(src_path, dst_path)


def get_reflog_action():
    """Get the reflog action from the environment variables.
    If not found, then check if we're in a rebase or merge.
    """
    reflog_action = os.environ.get('GIT_REFLOG_ACTION')
    
    if reflog_action is None:
        # if either the rebase-apply or rebase-merge directories exist, then we're in a rebase
        if os.path.exists(os.path.join('.git', 'rebase-apply')) or \
        os.path.exists(os.path.join('.git', 'rebase-merge')):
            reflog_action = "rebase"
        else:
            logger.info(f"No reflog action found, using merge strategy")
            reflog_action = "merge"
    elif "merge" in reflog_action:
        reflog_action = "merge"
    elif "rebase" in reflog_action:
        reflog_action = "rebase"
    else:
        logger.info(f"Unknown reflog action, using merge strategy: {reflog_action}")
        reflog_action = "merge"
    
    return reflog_action


def check_files_exist(ancestor_file, current_file, other_file, path_name):
    """Check if the files exist"""
    if not os.path.exists(ancestor_file):
        logger.error(f"Ancestor file does not exist: {ancestor_file}")
        return False
    if not os.path.exists(current_file):
        logger.error(f"Current file does not exist: {current_file}")
        return False
    if not os.path.exists(other_file):
        logger.error(f"Other file does not exist: {other_file}")
        return False
    if not os.path.exists(path_name):
        logger.error(f"Path name does not exist: {path_name}")
        return False
    return True


def main():
    """The ARK merge driver."""
    parser = argparse.ArgumentParser(
        description="Git merge driver using AI inference",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
To use Google's Gemini Model:
  - Set the GOOGLE_GEMINI_API_KEY environment variable

To use Anthropic's Claude Model:
  - Set the ANTHROPIC_API_KEY environment variable

Conflict resolution strategies:
  rebase: take their (upstream) code and apply our RHEL changes to it
  merge: take our (RHEL) code and apply the upstream changes to it
  backport (NOT SUPPORTED): agentically take our (RHEL) code and apply the upstream changes to it

To enable the git mergetool:

  - Configure git (include --local to set this only for the current repository):
    git config merge.tool ark-md
    git config mergetool.ark-md.cmd 'ark-merge-driver mergetool $BASE $LOCAL $REMOTE $MERGED'
    git config mergetool.ark-md.trustExitCode true
    git config mergetool.ark-md.guiDefault false
    git config mergetool.ark-md.prompt false

To enable the git merge driver:

  - Configure git (include --local to set this only for the current repository):
    git config merge.ark-md.driver 'ark-merge-driver driver %O %A %B %L %P'
    git config merge.ark-md.name 'kernel-ark merge driver'

  - Add the following to .gitattributes or .git/info/attributes:
    * merge=ark-md

        """
    )
    
    # Create subparsers for different operating modes
    subparsers = parser.add_subparsers(dest='mode', help='Operating mode', required=True)
    
    # Common arguments shared by both modes
    def add_common_arguments(subparser):
        subparser.add_argument("--debug", "-d", action="store_true",
                              help="Enable debug output")
        subparser.add_argument("--artifacts", action="store_true",
                              help="Save artifacts from the merge conflict.")
        subparser.add_argument("--strategy", choices=["rebase", "merge", "backport"],
                              help="AI strategy to use for resolving conflicts. If not specified, the strategy will be determined by the reflog action.")
        subparser.add_argument("--color", action="store_true",
                              help="Enable colored log output")
        subparser.add_argument("--without-ai", action="store_true",
                              help="Disable AI-based merge conflict resolution. Only use git's default merge strategy.")
    
    # Driver mode: Used by git merge driver
    driver_parser = subparsers.add_parser('driver', 
                                         help='Git merge driver mode (called by git during merges)')
    driver_parser.add_argument("ancestor_file", help="Ancestor (base) file path")
    driver_parser.add_argument("current_file", help="Current (ours/LOCAL) file path")
    driver_parser.add_argument("other_file", help="Other (theirs/REMOTE) file path")
    driver_parser.add_argument("conflict_size", type=int, help="Conflict marker size")
    driver_parser.add_argument("path_name", help="File path name")
    add_common_arguments(driver_parser)
    
    # Mergetool mode: Used as git mergetool
    mergetool_parser = subparsers.add_parser('mergetool',
                                           help='Git mergetool mode (called manually or by git mergetool)')
    mergetool_parser.add_argument("ancestor_file", help="Ancestor (base) file path")
    mergetool_parser.add_argument("current_file", help="Current (ours/LOCAL) file path")
    mergetool_parser.add_argument("other_file", help="Other (theirs/REMOTE) file path")
    mergetool_parser.add_argument("path_name", help="File path name")
    add_common_arguments(mergetool_parser)
    
    args = parser.parse_args()

    # Setup logging with optional colors
    global logger
    logger = setup_logging(use_colors=args.color)
    logger.setLevel(logging.DEBUG if args.debug else logging.INFO)
    logger.handlers[0].setLevel(logging.DEBUG if args.debug else logging.INFO)

    logger.info(f"Resolving merge conflict for: {args.path_name}")
    logger.debug(f"Ancestor: {args.ancestor_file}")
    logger.debug(f"Current: {args.current_file}")
    logger.debug(f"Other: {args.other_file}")
    logger.debug(f"Path name: {args.path_name}")
    logger.debug(f"AI enabled: {not args.without_ai}")
    logger.debug(f"Mode: {args.mode}")
    
    if not check_files_exist(args.ancestor_file, args.current_file, args.other_file, args.path_name):
        return 1
    
    if args.mode == "driver":
        # First, see if git can resolve the merge.
        # (I've not seen any of the other algorithms result in a successful
        # merge if myers fails but let's keep it for now.)
        diff_algorithms = ["myers", "minimal", "patience", "histogram"]
        for diff_algorithm in diff_algorithms:
            merge_success = run_git_merge_file(
                args.ancestor_file,
                args.current_file,
                args.other_file,
                args.conflict_size,
                args.path_name,
                args.artifacts,
                write_conflict = args.without_ai,
                diff_algorithm = diff_algorithm
            )
            if merge_success:
                break
        
        if merge_success:
            logger.info("Merge conflict resolved by git")
            return 0
    
    if args.without_ai:
        logger.info("AI merge conflict resolution disabled")
        return 1
    
    if args.artifacts:
        copy_file(args.ancestor_file, "ancestor-base")
        copy_file(args.current_file, "current-ours")
        copy_file(args.other_file, "other-theirs")
    
    if args.strategy is None:
        reflog_action = get_reflog_action()
    else:
        reflog_action = args.strategy
    
    logger.debug(f"Strategy: {reflog_action}")
    
    ai_provider = get_ai_provider()
    
    if ai_provider:
        merge_success = resolve_with_ai(
            ai_provider,
            args.ancestor_file,
            args.current_file,
            args.other_file,
            args.path_name,
            reflog_action,
            args.mode
        )
    else:
        merge_success = False

    if merge_success:
        logger.info("Merge conflict resolved.")
        return 0
    else:
        logger.error("Failed to resolve merge conflict.")
        # a bit of a hack: have git create the conflict file for us
        if args.mode == "driver":
            merge_success = run_git_merge_file(
                args.ancestor_file,
                args.current_file,
                args.other_file,
                args.conflict_size,
                args.path_name,
                args.artifacts,
                write_conflict = True
            )
        return 1

if __name__ == "__main__":
    sys.exit(main())
