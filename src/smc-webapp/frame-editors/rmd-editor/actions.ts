/*
R Markdown Editor Actions
*/

import { Actions } from "../markdown-editor/actions";
import { convert } from "./rmd2md";
import { FrameTree } from "../frame-tree/types";

export class RmdActions extends Actions {
  _init(...args): void {
    super._init(...args); // call the _init for the parent class
    if (!this.is_public) {
      // one extra thing after markdown.
      this._init_rmd2md();
    }
  }

  _init_rmd2md(): void {
    this._syncstring.on("save-to-disk", () => this._run_rmd2md());
    this._run_rmd2md();
  }

  async _run_rmd2md(time?: number): Promise<void> {
    // TODO: should only run knitr if at least one frame is visible showing preview?
    // maybe not, since might want to show error.
    this.set_status("Running knitr...");
    let markdown: string;
    try {
      markdown = await convert({
        path: this.path,
        project_id: this.project_id,
        time
      });
    } catch (err) {
      this.set_error(err);
      return;
    }
    this.setState({ content: markdown });
  }

  _raw_default_frame_tree(): FrameTree {
    if (this.is_public) {
      return { type: "cm" };
    } else {
      return {
        direction: "col",
        type: "node",
        first: {
          type: "cm"
        },
        second: {
          type: "markdown"
        }
      };
    }
  }
}