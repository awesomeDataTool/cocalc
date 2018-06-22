/*
Redux actions for nbviewer.
*/

const { Actions } = require("../smc-react");
const { cm_options } = require("./cm_options");
import { fromJS } from "immutable";
const cell_utils = require("./cell-utils"); // TODO: import types
const { JUPYTER_MIMETYPES } = require("./util");
const { IPynbImporter } = require("./import-from-ipynb"); // TODO: import types

export class NBViewerActions extends Actions {
  private store: any; // TODO: type
  private client: any; // TODO: type
  private redux: any; // TODO: type
  private _state: "ready" | "closed";
  _init = (project_id: string, path: any, store: any, client: any, content: any) => {
    this.store = store;
    if (client == null && content == null) {
      throw Error("@client or content must be defined");
    }
    this.client = client;
    this.setState({
      project_id,
      path,
      font_size:
        this.redux.getStore("account") && this.redux.getStore("account").get("font_size", 14)
    });
    this._state = "ready";
    if (content == null) {
      return this.load_ipynb();
    }
    // optionally specify the pre-loaded content of the path directly.
    try {
      return this.set_from_ipynb(JSON.parse(content));
    } catch (err) {
      this.setState({ error: `Error parsing -- ${err}` });
    }
  };

  load_ipynb = () => {
    if (this.store.get("loading")) {
      return;
    }
    this.setState({ loading: new Date() });
    // TODO: is this return required?
    return this.client.public_get_text_file({
      project_id: this.store.get("project_id"),
      path: this.store.get("path"),
      // TODO: rewrite with async
      cb: (err: any, data: any) => {
        if (this._state === "closed") {
          return;
        }
        this.setState({ loading: undefined });
        if (err) {
          return this.setState({ error: `Error loading -- ${err}` });
        }
        try {
          return this.set_from_ipynb(JSON.parse(data));
        } catch (error) {
          this.setState({ error: `Error parsing -- ${error}` });
        }
      }
    });
  };

  _process = (content: any) => {
    if (content.data == null) {
      return;
    }
    for (let type of JUPYTER_MIMETYPES) {
      if (
        content.data[type] != null &&
        (type.split("/")[0] === "image" || type === "application/pdf")
      ) {
        content.data[type] = { value: content.data[type] };
      }
    }
  };

  set_from_ipynb = (ipynb: any) => {
    const importer = new IPynbImporter();
    importer.import({
      ipynb,
      output_handler: (cell: any) => {
        let k = 0;
        return {
          message: content => {
            this._process(content);
            cell.output[`${k}`] = content;
            return (k += 1);
          }
        };
      }
    });

    const cells = fromJS(importer.cells());
    const cell_list = cell_utils.sorted_cell_list(cells);

    let mode: string | undefined = undefined;
    if (
      ipynb.metadata &&
      ipynb.metadata.language_info &&
      ipynb.metadata.language_info.codemirror_mode
    ) {
      mode = ipynb.metadata.language_info.codemirror_mode;
    } else if (
      ipynb.metadata &&
      ipynb.metadata.language_info &&
      ipynb.metadata.language_info.name
    ) {
      mode = ipynb.metadata.language_info.name;
    } else if (ipynb.metadata && ipynb.metadata.kernelspec && ipynb.metadata.kernelspec.language) {
      mode = ipynb.metadata.kernelspec.language.toLowerCase();
    }
    const options = fromJS({
      markdown: undefined,
      options: cm_options(mode)
    });
    return this.setState({
      cells,
      cell_list,
      cm_options: options
    });
  };
  close = () => {
    delete this.store;
    delete this.client;
    return (this._state = "closed");
  };
}